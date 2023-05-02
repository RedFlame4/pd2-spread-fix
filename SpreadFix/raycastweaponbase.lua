local mvec_to = Vector3()
local mvec_right_ax = Vector3()
local mvec_up_ay = Vector3()
local mvec_ax = Vector3()
local mvec_ay = Vector3()
local mvec_spread_direction = Vector3()

function RaycastWeaponBase:_fire_raycast(user_unit, from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul)
	if self:gadget_overrides_weapon_functions() then
		return self:gadget_function_override("_fire_raycast", self, user_unit, from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul)
	end

	local result = {}
	local ray_distance = self:weapon_range()
	local spread_x, spread_y = self:_get_spread(user_unit)
	spread_y = spread_y or spread_x
	spread_mul = spread_mul or 1

	mvector3.cross(mvec_right_ax, direction, math.UP)
	mvector3.normalize(mvec_right_ax)
	mvector3.cross(mvec_up_ay, direction, mvec_right_ax)
	mvector3.normalize(mvec_up_ay)
	mvector3.set(mvec_spread_direction, direction)

	local r = math.random()
	local theta = math.random() * 360
	spread_x = math.max(math.min(spread_x * spread_mul, 90), -90)
	spread_y = math.max(math.min(spread_y * spread_mul, 90), -90)

	mvector3.multiply(mvec_right_ax,  math.cos(theta) * math.tan(r * spread_x))
	mvector3.multiply(mvec_up_ay, -1 * math.sin(theta) * math.tan(r * spread_y))
	mvector3.add(mvec_spread_direction, mvec_right_ax)
	mvector3.add(mvec_spread_direction, mvec_up_ay)
	mvector3.set(mvec_to, mvec_spread_direction)
	mvector3.multiply(mvec_to, ray_distance)
	mvector3.add(mvec_to, from_pos)

	local ray_hits, hit_enemy = self:_collect_hits(from_pos, mvec_to)
	local auto_hit_candidate, suppression_enemies = self:check_autoaim(from_pos, direction)

	if suppression_enemies and self._suppression then
		result.enemies_in_cone = suppression_enemies
	end

	if self._autoaim then
		local weight = 0.1

		if auto_hit_candidate and not hit_enemy then
			local autohit_chance = 1 - math.clamp((self._autohit_current - self._autohit_data.MIN_RATIO) / (self._autohit_data.MAX_RATIO - self._autohit_data.MIN_RATIO), 0, 1)

			if autohit_mul then
				autohit_chance = autohit_chance * autohit_mul
			end

			if math.random() < autohit_chance then
				self._autohit_current = (self._autohit_current + weight) / (1 + weight)

				mvector3.set(mvec_spread_direction, auto_hit_candidate.ray)
				mvector3.set(mvec_to, mvec_spread_direction)
				mvector3.multiply(mvec_to, ray_distance)
				mvector3.add(mvec_to, from_pos)

				ray_hits, hit_enemy = self:_collect_hits(from_pos, mvec_to)
			end
		end

		if hit_enemy then
			self._autohit_current = (self._autohit_current + weight) / (1 + weight)
		elseif auto_hit_candidate then
			self._autohit_current = self._autohit_current / (1 + weight)
		end
	end

	local hit_count = 0
	local hit_anyone = false
	local cop_kill_count = 0
	local hit_through_wall = false
	local hit_through_shield = false
	local is_civ_f = CopDamage.is_civilian
	local damage = self:_get_current_damage(dmg_mul)

	for _, hit in ipairs(ray_hits) do
		local dmg = self:get_damage_falloff(damage, hit, user_unit)

		if dmg > 0 then
			local hit_result = self._bullet_class:on_collision(hit, self._unit, user_unit, dmg)

			if hit_result then
				hit.damage_result = hit_result
				hit_anyone = true
				hit_count = hit_count + 1

				if hit_result.type == "death" then
					local unit_type = hit.unit:base() and hit.unit:base()._tweak_table
					local is_civilian = unit_type and is_civ_f(unit_type)

					if not is_civilian then
						cop_kill_count = cop_kill_count + 1
					end

					hit_through_wall = hit_through_wall or hit.unit:in_slot(self.wall_mask)
					hit_through_shield = hit_through_shield or hit.unit:in_slot(self.shield_mask) and alive(hit.unit:parent())

					self:_check_kill_achievements(cop_kill_count, unit_type, is_civilian, hit_through_wall, hit_through_shield)
				end
			end
		end
	end

	self:_check_tango_achievements(cop_kill_count)

	result.hit_enemy = hit_anyone

	if self._autoaim then
		self._shot_fired_stats_table.hit = hit_anyone
		self._shot_fired_stats_table.hit_count = hit_count

		if (not self._ammo_data or not self._ammo_data.ignore_statistic) and not self._rays then
			managers.statistics:shot_fired(self._shot_fired_stats_table)
		end
	end

	local furthest_hit = ray_hits[#ray_hits]

	if (not furthest_hit or furthest_hit.distance > 600) and alive(self._obj_fire) then
		self._obj_fire:m_position(self._trail_effect_table.position)
		mvector3.set(self._trail_effect_table.normal, mvec_spread_direction)

		local trail = World:effect_manager():spawn(self._trail_effect_table)

		if furthest_hit then
			World:effect_manager():set_remaining_lifetime(trail, math.clamp((furthest_hit.distance - 600) / 10000, 0, furthest_hit.distance))
		end
	end

	if self._alert_events then
		result.rays = ray_hits
	end

	return result
end