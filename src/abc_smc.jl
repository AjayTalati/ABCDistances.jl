##NB THIS IS AN ADAPTIVE VERSION. I ALSO NEED A STANDARD VERSION. ADD AN ARGUMENT OR MAKE A NEW METHOD?
##k is how many particles to accept each time
function doABCSMC(abcinput::ABCInput, nparticles::Integer, k::Integer, maxsims::Integer) ##Should this be a constructor? Does it need its own output type?
    iteration = 1
    ##First iteration is just standard rejection sampling
    curroutput = ABCOutput(abcinput, nparticles)
    ##TO DO: Consider some stopping conditions? (e.g. threshold = 0) Call a "stopearly" method?
    norms = [curroutput.abcnorm]
    thresholds = [curroutput.distances[k]]
    output = [curroutput]
    simsdone = nparticles
    ##Main loop
    while (simsdone < maxsims)
        iteration++
        ##Calculate variance of current weighted particle approximation
        currvar = cov(curroutput.parameters, WeightVec(curroutput.weights))
        perturbdist = MvNormal(2.0 .* currvar)
        ##Initialise new reference table
        newparameters = Array(Float64, (abcinput.nparameters, nparticles))
        newsumstats = Array(Float64, (abcinput.nsumstats, nparticles))
        newabsdiffs = Array(Float64, (abcinput.nsumstats, nparticles))
        nextparticle = 1
        ##Loop to fill up new reference table
        while (nextparticle <= nparticles && totalsims<maxsims)
            ##Sample parameters from importance density
            proppars = rimportance(curroutput, perturbdist)
            ##Draw summaries
            propstats = abcinput.data2sumstats(abcinput.rdata(proppars))
            absdiff = abs(abcinput.sobs-propstats)
            simsdone++
            ##Accept if all prev norms less than corresponding thresholds.
            if propgood(absdiff, norms, thresholds)
                newparameters[:,nextparticle] = proppars
                newsumstats[:,nextparticle] = propstats
                newabsdiffs[:,nextparticle] = absdiff
                nextparticle++
            end
        end
        ##Stop if not all sims required to continue have been done (because totalsims==maxsims)
        if nextparticle<=nparticles
            continue
        end
        ##Initialise new norm
        newnorm = init(abcinput.abcnorm, newsumstats)
        push!(norms, newnorm)
        ##Calculate distances
        distances = [ evalnorm(newnorm, newabsdiffs[:,i]) for i=1:nparticles ]
        oldoutput = copy(curroutput)
        curroutput = ABCOutput(nparticles, newparameters, newsumstats, newdistances, zeros(nparticles), newnorm) ##Set new weights to zero for now
        sortABCOutput!(curroutput)
        ##Calculate and use new threshold
        push!(thresholds, curroutput.distances[k])
        curroutput.parameters = curroutput.parameters[:,1:k]
        curroutput.sumstats = curroutput.sumstats[:,1:k]
        curroutput.distances = curroutput.distances[1:k]
        curroutput.weights = getweights(curroutput, abcinput, oldoutput, perturbdist)
        ##Record output
        push!(output, curroutput)
        ##Report status
        print("Iteration $iteration, $totalsims sims done\n")
        print("Output of most recent stage:\n")
        print(curroutput)
        ##Make some plots as well?
        ##Consider alternative stopping conditions? (e.g. zero threshold reached)
    end
    output
end

##Check if summary statistics meet all of previous acceptance requirements
function propgood(absdiff::Array, norms::Array, thresholds::Array)
    ##TO DO: be more specific about types of arguments?
    for i in 1:length(norms)
        if evalnorm(norms[i], absdiff)>thresholds[i]
            return false
        end
    end
    return true
end

##Samples from importance density defined by prev output
function rimportance(x::ABCOutput, dist::MvNormal)
    i = sample(WeightVec(x.weights))
    x.parameters[:,i] + rand(dist)
end

##Calculate a single importance weight
function get1weight(x::Array{Float64,1}, in::ABCInput, old::ABCOutput, perturbdist::MvNormal)
    temp = [pdf(perturbdist, x-old.parameters[:,i]) for i in 1:nsims]
    in.dprior(x) / sum(old.weights .* temp)
end

##Calculates importance weights
function getweights(current::ABCOutput, in::ABCInput, old::ABCOutput, perturbdist::MvNormal)
    weights = [get1weight(current.parameters[:,i], in, old, perturbdist) for i in 1:current.nsims]
    weights ./ sum(weights)
end