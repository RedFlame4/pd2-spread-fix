local mto = Vector3()
local mfrom = Vector3()
local mspread = Vector3()

function PlayerTurretBase:auto_fire_blank(direction)
	local user_unit = self._setup.user_unit

	if self._obj_fire then
		self._obj_fire:m_position(mfrom)
	else
		self._unit:m_position(mfrom)
	end

	local rays = {}
	local right = direction:cross(math.UP):normalized()
	local up = direction:cross(right):normalized()
	local spread_x, spread_y = self:_get_spread()
	spread_y = spread_y or spread_x 

	local r = math.random()
	local theta = math.random() * 360
	spread_x = math.max(math.min(spread_x, 90), -90)
	spread_y = math.max(math.min(spread_y, 90), -90)

	local ax = math.cos(theta) * math.tan(r * spread_x)
	local ay = -1 * math.sin(theta) * math.tan(r * spread_y)

	mvector3.set(mspread, direction)
	mvector3.add(mspread, right * ax)
	mvector3.add(mspread, up * ay)
	mvector3.set(mto, mspread)
	mvector3.multiply(mto, 20000)
	mvector3.add(mto, mfrom)

	local col_ray = World:raycast("ray", mfrom, mto, "slot_mask", self._blank_slotmask, "ignore_unit", self._setup.ignore_units)

	if alive(self._obj_fire) then
		self._obj_fire:m_position(self._trail_effect_table.position)
		mvector3.set(self._trail_effect_table.normal, mspread)
	end

	local trail = nil

	if not self:weapon_tweak_data().no_trail then
		trail = alive(self._obj_fire) and (not col_ray or col_ray.distance > 650) and World:effect_manager():spawn(self._trail_effect_table) or nil
	end

	if col_ray then
		if alive(user_unit) then
			InstantBulletBase:on_collision(col_ray, self._unit, user_unit, self._damage, true)
		end

		if trail then
			World:effect_manager():set_remaining_lifetime(trail, math.clamp((col_ray.distance - 600) / 10000, 0, col_ray.distance))
		end

		table.insert(rays, col_ray)
	end

	if alive(self._obj_fire) then
		self:_spawn_muzzle_effect(mfrom, direction)
	end

	if self._use_shell_ejection_effect then
		World:effect_manager():spawn(self._shell_ejection_effect_table)
	end

	if self:weapon_tweak_data().has_fire_animation then
		self:tweak_data_anim_play("fire", self:fire_rate_multiplier())
	end

	if alive(user_unit) and user_unit:movement() then
		local anim_data = user_unit:anim_data()

		if not anim_data or not anim_data.reload then
			user_unit:movement():play_redirect("recoil_single")
		end
	end

	self:play_tweak_data_sound("fire_single_npc", "fire_single")

	return true
end