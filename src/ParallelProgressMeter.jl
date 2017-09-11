__precompile__()

module ParallelProgressMeter

export initializeProgress

#copied from https://github.com/timholy/ProgressMeter.jl
function move_cursor_up_while_clearing_lines(io, numlinesup)
    [print(io, "\u1b[1G\u1b[K\u1b[A") for _ in 1:numlinesup]
end

#copied from https://github.com/timholy/ProgressMeter.jl
function printover(io::IO, s::AbstractString, color::Symbol = :color_normal)
    if isdefined(Main, :IJulia) || isdefined(Main, :ESS) || isdefined(Main, :Atom)
        print(io, "\r" * s)
    else
        print(io, "\u1b[1G")   # go to first column
        print_with_color(color, io, s)
        print(io, "\u1b[K")    # clear the rest of the line
    end
end

function convertSeconds(s::Float64)
#convert a time in seconds into the format HH:MM:SS
    H = floor(Int64, s/(60*60))
    M = floor(Int64, (s - 60*60*H)/60)
    S = round(Int64, s - 60*60*H - 60*M)
    string(lpad(H, 2, 0), ":", lpad(M, 2, 0), ":", lpad(S, 2, 0))
end

function calcETA(p::Float64, d::Float64, delay::Float64)
#calculates ETA in the format HH:MM:SS given a percent progress and the elapsed time
    if p == 100
        "00:00:00"
    elseif (p == 0) | (d == 0)
        "NA"
    else
        remaining = delay*(100-p)/d
        convertSeconds(remaining)
    end
end



function monitorProgress!(progressArray::SharedArray{Int64,1}, numArray::Array{Int64, 1}, delay::Float64)
#reads changes to progressArray, calculates ETA of each task, and prints one line for each task with progress
#percent and ETA.  Stops when the entire progress array is at 100% 
    t = time()
    startTime = t
    for a in 1:length(progressArray)
        println(string("Progress of task ", lpad(a, 2, 0), " is 00.00 %     ETA: NA"))
    end
    
    currentProgress = round(100*progressArray./numArray, 2)
    completeProgress = fill!(similar(currentProgress), 100)
    deltaProgress = fill!(similar(currentProgress), 0)
    lastProgress = currentProgress

    message(a) = println(string("Progress of task ", lpad(a, 2, 0), " is ", rpad(currentProgress[a], 5, 0), "%     ETA: ", calcETA(currentProgress[a], deltaProgress[a], delay)))
    
    while currentProgress != completeProgress   
        currentProgress = round(100*progressArray./numArray, 2)
        if (time() - t) > delay
            deltaProgress = currentProgress - lastProgress
            move_cursor_up_while_clearing_lines(STDOUT, length(progressArray))
            for a in 1:length(progressArray)
                message(a)
            end
            t = time()
            lastProgress = currentProgress
        end
    end
    move_cursor_up_while_clearing_lines(STDOUT, length(progressArray))
    for a in 1:length(progressArray)
        message(a)
    end
    println(string("Parallel progress monitor complete after ", convertSeconds(time() - startTime)))
    println("")
end

function initializeProgress(numTasks::Int64, numArray::Array{Int64, 1}, delay::Float64 = 1.0)
#initializes shared progressArray, starts running monitorProgress! asynchronously, and returns 
#progressArray for later useremote channel for later use.  numTasks should match the 
#size of the parallel for loop while numArray should be the number of iterations per task and 
#have the same number of elements as numTasks
    
    if numTasks > nprocs()
        println(string("Warning: number of parallel tasks is greater than or equal to the ", nprocs(), " workers so tasks may be delayed executing"))
        println("For a parallel for loop it is recommended to have a worker added for each parallel task in addition to the primary worker launching the loop")
    end

    if numTasks > Sys.CPU_CORES
        println(string("Warning: number of parallel tasks exceeds the ", Sys.CPU_CORES, " available cores so tasks maybe execute more slowly"))
    end

    @assert numTasks == length(numArray) ["The array of iteration lengths is not the same size as the number of tasks"]
    
    #progArray stores the number of iterations each loop has progressed
    progArray = SharedArray(Int64, numTasks)

    #initialize update monitor that will record and print the progress of
    #each serial task
    @async monitorProgress!(progArray, numArray, delay)

    return progArray
end

end # module
