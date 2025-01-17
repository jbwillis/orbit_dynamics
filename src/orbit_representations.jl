# Code for converting between different orbit representations

export equinoctial_to_classical_elements
"""
Reference: https://spsweb.fltops.jpl.nasa.gov/portaldataops/mpg/MPG_Docs/Source%20Docs/EquinoctalElements-modified.pdf
"""
function equinoctial_to_classical_elements(x_eq)
	p, f, g, h, k, L = x_eq

	a = p / (1 - f^2 - g^2)
	e = sqrt(f^2 + g^2)
	i = atan(2*sqrt(h^2 + k^2), 1 - h^2 - k^2)
	omega = atan(g*h - f*k, f*h + g*k)
	Omega = atan(k, h)
	theta = L - (Omega + omega)

	omega = rem2pi(omega, RoundDown)
	Omega = rem2pi(Omega, RoundDown)
	theta = rem2pi(theta, RoundDown)

	return [a, e, i, omega, Omega, theta]
end

export classical_to_equinoctial_elements
"""
Reference: https://spsweb.fltops.jpl.nasa.gov/portaldataops/mpg/MPG_Docs/Source%20Docs/EquinoctalElements-modified.pdf
"""
function classical_to_equinoctial_elements(x_cl)
	a, e, i, omega, Omega, theta = x_cl
	
	p = a * (1 - e^2)
	f = e * cos(omega + Omega)
	g = e * sin(omega + Omega)
	h = tan(i/2) * cos(Omega)
	k = tan(i/2) * sin(Omega)
	L = Omega + omega + theta


	return [p, f, g, h, k, L]
end

export classical_to_state_vector
"""
Reference: Fundamentals of Spacecraft Attitude Determination and Control, pg 380
"""
function classical_to_state_vector(x_cl, dp::DynamicsParameters)
	a, e, i, omega, Omega, theta = x_cl

	A11 = cos(Omega) * cos(omega) - sin(Omega) * sin(omega) * cos(i)
	A12 = sin(Omega) * cos(omega) + cos(Omega) * sin(omega) * cos(i)
	A13 = sin(omega) * sin(i)

	A21 = -cos(Omega) * sin(omega) - sin(Omega) * cos(omega) * cos(i)
	A22 = -sin(Omega) * sin(omega) + cos(Omega) * cos(omega) * cos(i)
	A23 = cos(omega) * sin(i)

	A = [A11 A21; A12 A22; A13 A23]

	n = sqrt(dp.mu/a^3)
	E = E_from_theta(theta, e)
	
	r_mag = a*(1 - e*cos(E))
	x_peri = a*(cos(E) - e)
	y_peri = a * sqrt(1-e^2) * sin(E)
	x_dot_peri = -(n*a^2/r_mag) * sin(E)
	y_dot_peri = (n*a^2/r_mag) * sqrt(1-e^2) * cos(E)

	r_vec = A * [x_peri; y_peri]

	v_vec = A * [x_dot_peri; y_dot_peri]

	return vcat(r_vec, v_vec)
end

export equinoctial_to_state_vector
"""
Reference: https://spsweb.fltops.jpl.nasa.gov/portaldataops/mpg/MPG_Docs/Source%20Docs/EquinoctalElements-modified.pdf
"""
function equinoctial_to_state_vector(x_eq, dp::DynamicsParameters)
	p, f, g, h, k, L = x_eq

	alpha_sq = h^2 - k^2
	s_sq = 1 + h^2 + k^2
	w = 1 + f*cos(L) + g*sin(L)
	r = p/w

	r_x = (r/s_sq) * (cos(L) + alpha_sq * cos(L) + 2*h*k*sin(L))
	r_y = (r/s_sq) * (sin(L) - alpha_sq * sin(L) + 2*h*k*cos(L))
	r_z = (2*r/s_sq) * (h*sin(L) - k*cos(L))

	v_x = (-1/s_sq) * sqrt(dp.mu/p) * (sin(L) + alpha_sq*sin(L) - 2*h*k*cos(L) + g - 2*f*h*k + alpha_sq*g)
	v_y = (-1/s_sq) * sqrt(dp.mu/p) * (-cos(L) + alpha_sq*cos(L) + 2*h*k*sin(L) - f + 2*g*h*k + alpha_sq*f)
	v_z = (2/s_sq) * sqrt(dp.mu/p) * (h*cos(L) + k*sin(L) + f*h + g*k)

	return [r_x, r_y, r_z, v_x, v_y, v_z]
end

export state_vector_to_equinoctial_elements
"""
"""
function state_vector_to_equinoctial_elements(x_st, dp::DynamicsParameters)

	# need better method for this
	x_cl = state_vector_to_classical_elements(x_st, dp)
	x_eq = classical_to_equinoctial_elements(x_cl)

	return x_eq
end

export state_vector_to_classical_elements
"""
Source: Followed https://github.com/sisl/SatelliteDynamics.jl/blob/master/src/astrodynamics.jl#L248
"""
function state_vector_to_classical_elements(x_st, dp::DynamicsParameters)

	r = x_st[1:3]
	v = x_st[4:6]

	h = cross(r, v)
	W = h/norm(h)

	i = atan(sqrt(W[1]^2 + W[2]^2), W[3])
	Omega = atan(W[1], -W[2])

	p = norm(h)^2/dp.mu
	a = 1.0/(2.0/norm(r) - norm(v)^2/dp.mu)

	# numerical stability hack for circular/near circular orbits
	# ensures that (1-p/a) is always positive
	if isapprox(a, p, atol=1e-9, rtol=1e-8)
		p = a
	end

	n = sqrt(dp.mu/(a^3)) # mean motion
	e = sqrt(1 - p/a) # eccentricity
	E = atan(dot(r, v)/(n*a^2), (1 - norm(r)/a)) # eccentric anomaly
	u = atan(r[3], -r[1]*W[2] + r[2]*W[1]) # mean longitude
	theta = atan(sqrt(1-e^2)*sin(E), cos(E) - e) # true anomaly
	omega = u - theta # argument of perigee

	omega = rem2pi(omega, RoundDown)
	Omega = rem2pi(Omega, RoundDown)
	theta = rem2pi(theta, RoundDown)

	return [a, e, i, omega, Omega, theta]
end

export E_from_M
function E_from_M(M, e; tol=1e-10)
    f(E) = E - e * sin(E) - M # = 0
    f_prime(E) = 1 - e * cos(E)
    
    # solve for E using Newton's method
    E_n = M
    while abs( f(E_n) ) > tol
        E_n = E_n - f(E_n)/f_prime(E_n)
    end
    
    return E_n
end

export theta_from_E
function theta_from_E(E, e)
    return atan(sqrt(1-e^2) * sin(E), cos(E) - e)
end

export E_from_theta
function E_from_theta(theta, e)
    return atan(sqrt(1 - e^2) * sin(theta), cos(theta) + e)
end

export M_from_E
function M_from_E(E, e)
    return E - e * sin(E)
end

export specific_mechanical_energy
"""
Compute the specific mechanical energy of a given set of orbit states
"""
function specific_mechanical_energy(x_rv, x_cl, dp::DynamicsParameters)

	a, e, i, omega, Omega, theta = x_cl

	r_mag = norm(x_rv[1:3])
	v_mag = norm(x_rv[4:6])


	c_phi = sin(i) * sin(theta + omega)
	P2 = 0.5 * (3 * c_phi^2 - 1)
	U_J2 = (-dp.mu / r_mag) * dp.J2 * (dp.R_earth / r_mag)^2 * P2

	# u_J2 = gravity_perturbation_classical(x_cl, dp)
	# U_J2 = norm(u_J2)
	# u_J2 = gravity_perturbation_ECI(x_rv, dp)
	# U_J2 = norm(u_J2)
	
	sme = 0.5 * (v_mag^2) - (dp.mu / r_mag) - U_J2

	return sme

end

export unscale_state_vector
"""
Convert ECI vector [r; v] from scaled units to unscaled (SI) units
"""
function unscale_state_vector(x_scaled, dp::DynamicsParameters)

	x_unscaled = copy(x_scaled)
	x_unscaled[1:3] *= dp.distance_scale
	x_unscaled[4:6] *= (dp.distance_scale/dp.time_scale)
	
	return x_unscaled
end

export unscale_state_vector_dot
"""
Convert ECI vector [v; a] from scaled units to unscaled (SI) units
"""
function unscale_state_vector_dot(x_dot_scaled, dp::DynamicsParameters)

	x_dot_unscaled = copy(x_dot_scaled)
	x_dot_unscaled[1:3] *= (dp.distance_scale/dp.time_scale)
	x_dot_unscaled[4:6] *= (dp.distance_scale/dp.time_scale^2)
	
	return x_dot_unscaled
end

export scale_state_vector
"""
Convert ECI vector [r; v] from unscaled (SI) units to scaled units
"""
function scale_state_vector(x_unscaled, dp::DynamicsParameters)

	x_scaled = copy(x_unscaled)
	x_scaled[1:3] /= dp.distance_scale # m * dunit / m
	x_scaled[4:6] /= (dp.distance_scale/dp.time_scale)
	
	return x_scaled
end

export scale_state_vector_dot
"""
Convert ECI vector [v; a] from scaled units to unscaled (SI) units
"""
function scale_state_vector_dot(x_dot_unscaled, dp::DynamicsParameters)

	x_dot_scaled = copy(x_dot_unscaled)
	x_dot_scaled[1:3] /= (dp.distance_scale/dp.time_scale)
	x_dot_scaled[4:6] /= (dp.distance_scale/dp.time_scale^2)
	
	return x_dot_scaled
end

export pos_cartesian_to_cylindrical
function pos_cartesian_to_cylindrical(p)
    x, y, z = p
    
    r = (x^2 + y^2)^0.5
    θ = atan(y, x)
    h = z
    
    return [r, θ, h]
end

export vel_cartesian_to_cylindrical
function vel_cartesian_to_cylindrical(p, v)
    x, y, z = p
    xd, yd, zd = v
    
    rd = (x*xd + y*yd) / (x^2 + y^2)^(0.5)
    θd = (yd*x - xd*y) / (x^2 + y^2)
    hd = zd
    
    return [rd, θd, hd]
end

export accel_cartesian_to_cylindrical
function accel_cartesian_to_cylindrical(p, v, a)
    x, y, z = p
    xd, yd, zd = v
    xdd, ydd, zdd = a
    
    rdd = ((xd^2 + x*xdd + yd^2 + y*ydd) * ((x^2 + y^2)^(-0.5))) - (((x*xd + y*yd)^2) * ((x^2 + y^2)^(-1.5)))
    
    θdd = ((ydd*x - xdd*y) * ((x^2 + y^2)^(-1))) - ((yd*x - xd*y)*(2*x*xd + 2*y*yd) * ((x^2 + y^2)^(-2)))
    
    hdd = zdd
    
    return [rdd, θdd, hdd]
end

export state_cartesian_to_cylindrical
function state_cartesian_to_cylindrical(x)
    return [pos_cartesian_to_cylindrical(x[1:3]); vel_cartesian_to_cylindrical(x[1:3], x[4:6])]
end

export state_dot_cartesian_to_cylindrical
function state_dot_cartesian_to_cylindrical(x, xd)
    return [vel_cartesian_to_cylindrical(x[1:3], xd[1:3]); accel_cartesian_to_cylindrical(x[1:3], xd[1:3], xd[4:6])]
end

export pos_cylindrical_to_cartesian
function pos_cylindrical_to_cartesian(w)
    r, θ, h = w
    
    x = r*cos(θ)
    y = r*sin(θ)
    z = h
    
    return [x, y, z]
end

export vel_cylindrical_to_cartesian
function vel_cylindrical_to_cartesian(w, wd)
    r, θ, h = w
    rd, θd, hd = wd
    
    xd = rd * cos(θ) - r * θd * sin(θ)
    yd = rd * sin(θ) + r * θd * cos(θ)
    zd = hd
    
    return [xd, yd, zd]
end

export accel_cylindrical_to_cartesian
function accel_cylindrical_to_cartesian(w, wd, wdd)
    r, θ, h = w
    rd, θd, hd = wd
    rdd, θdd, hdd = wdd
   
    xdd = rdd*cos(θ) - 2*rd*θd*sin(θ) - r*θdd*sin(θ) - r*(θd^2)*cos(θ)
    ydd = rdd*sin(θ) + 2*rd*θd*cos(θ) + r*θdd*cos(θ) - r*(θd^2)*sin(θ)
    zdd = hdd
    
    return [xdd, ydd, zdd]
end

export state_cylindrical_to_cartesian
function state_cylindrical_to_cartesian(w)
    return [pos_cylindrical_to_cartesian(w[1:3]); vel_cylindrical_to_cartesian(w[1:3], w[4:6])]
end

export state_dot_cylindrical_to_cartesian
function state_dot_cylindrical_to_cartesian(w, wd)
    return [vel_cylindrical_to_cartesian(w[1:3], wd[1:3]); accel_cylindrical_to_cartesian(w[1:3], wd[1:3], wd[4:6])]
end
