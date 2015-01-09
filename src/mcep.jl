# Mel-cepstrum analysis
# re-coded from SPTK

function fill_al!{T<:FloatingPoint}(al::Vector{T}, α::FloatingPoint)
    al[1] = one(T)
    for i=2:length(al)
        @inbounds al[i] = -α*al[i-1]
    end
    al
end

function fill_toeplitz!{T}(A::AbstractMatrix{T}, t::AbstractVector{T})
    n = length(t)
    for i=1:n, j=1:n
        if i-j+1 >= 1
            @inbounds A[i,j] = t[i-j+1]
        else
            @inbounds A[i,j] = t[j-i+1]
        end
    end
    A
end

function fill_hankel!{T}(A::AbstractMatrix{T}, h::AbstractVector{T})
    n = length(h)>>1 + 1
    for i=1:n, j=1:n
        @inbounds A[i,j] = h[i+j-1]
    end
    A
end


function fill_only_real_part!{T}(y::AbstractVector{Complex{T}},
                                 v::AbstractVector{T})
    for i=1:length(v)
        @inbounds y[i] = Complex(v[i], zero(T))
    end
    y
end

function update_hankel_elements!(he::AbstractVector, c::AbstractVector)
    for j=1:length(he)
        @inbounds he[j] = c[j]
    end
    for j=1:2:length(he)
        @inbounds he[j] -= c[1]
    end
    he
end

function update_toeplitz_elements!(te::AbstractVector, c::AbstractVector)
    for j=1:2:length(te)
        @inbounds te[j] += c[1]
    end
    te
end

function _mcep{T<:FloatingPoint}(x::AbstractVector{T},           # a *windowed* signal
                                 order::Int=40,                  # order of mel-cepstrum
                                 α::FloatingPoint=0.41;          # all-pass constant
                                 miniter::Int=2,
                                 maxiter::Int=30,
                                 criteria::FloatingPoint=0.001,  # stopping criteria
                                 e::T=zero(T),                   # floor of periodogram
                                 verbose::Bool=false)
    const xh = length(x)>>1

    # create FFT workspace and plan
    y = Array(Complex{T}, xh+1)
    c = Array(T, length(x))
    fplan = FFTW.Plan(c, y, 1, FFTW.ESTIMATE, FFTW.NO_TIMELIMIT)
    bplan = FFTW.Plan(y, c, 1, FFTW.ESTIMATE, FFTW.NO_TIMELIMIT)

    # Periodogram
    FFTW.execute(fplan.plan, x, y)
    periodogram = abs2(y)
    logperiodogram = log(periodogram + e)

    # Initial value of cepstrum
    fill_only_real_part!(y, logperiodogram)
    FFTW.execute(bplan.plan, y, c)
    scale!(c, FFTW.normalization(c))
    c[1] /= 2.0
    c[xh+1] /= 2.0

    # Initial value of mel-cesptrum
    mc = freqt(sub(c, 1:xh+1), order, α)
    czero = c[1]

    # Allocate memory for solving linear equation (Tm + Hm)d = b
    Tm = Array(T, order+1, order+1)
    Hm = Array(T, order+1, order+1)
    Tm_plus_Hm = Array(T, order+1, order+1)
    he = Array(T, 2order+1) # elements of hankel matrix
    te = Array(T, order+1)  # elements of toeplitz matrix
    b = Array(T, order+1)   # right side of linear equation

    al = Array(T, order+1)
    fill_al!(al, α)

    # Newton raphson roop
    ch = sub(c, 1:xh+1)
    ch_copy = Array(T, xh+1)
    c_frqtr = sub(c, 1:2order+1)
    for i=1:maxiter
        fill!(c, zero(T))
        freqt!(ch, mc, -α)

        FFTW.execute(fplan.plan, c, y)
        for i=1:length(y)
            @inbounds y[i] = Complex(periodogram[i] / exp(2real(y[i])), zero(T))
        end
        FFTW.execute(bplan.plan, y, c)
        scale!(c, FFTW.normalization(c))

        copy!(ch_copy, ch)
        frqtr!(c_frqtr, ch_copy, α)

        # check convergence
        if i >= miniter
            err = abs((c[1]-czero)/c[1])
            verbose && println("czero nmse: $err")
            if err < criteria
                break
            end
            czero = c[1]
        end

        copy!(te, 1, c, 1, order+1)

        for j=1:order+1
            @inbounds b[j] = c[j] - al[j]
        end

        update_hankel_elements!(he, c)
        update_toeplitz_elements!(te, c)

        fill_hankel!(Hm, he)
        fill_toeplitz!(Tm, te)

        for i=1:order+1,j=1:order+1
            @inbounds Tm_plus_Hm[i,j] = Hm[i,j] + Tm[i,j]
        end

        # solve linear equation and add derivative
        mc += Tm_plus_Hm \ b
    end

    mc
end

function mcep{T<:FloatingPoint,N}(x::AbstractArray{T,N},
                                  order::Int=40,
                                  α::FloatingPoint=0.41;
                                  kargs...)
    raw = _mcep(x, order, α; kargs...)
    MelGeneralizedCepstrum{Mel,StandardLog,T,N}(α, zero(T), raw)
end
