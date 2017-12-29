--------------------
-- オプション
--------------------

-- 高度
CRUISE_ALT = 0 -- 表示高度ではなく原点の高度

--------------------
-- PID
--------------------
PidSetting = {}
PidSetting.new = function(p, i, d) 
    local self = {}
    self.kP = p
    self.Ti = i
    self.Td = d
    return self
  end

PidTurning = {}
PidTurning.CreateConfig = function(p, i, d) 
    local self = {}
    self.logs = {}
    self.current = PidSetting.new(p, i, d, s)
    self.total = 0
    return self
  end

ppid = PidTurning.CreateConfig(1.0, 400, 1) -- 1200 * 25msecs = 30secs
apid = PidTurning.CreateConfig(1.0, 1200, 1)
rpid = PidTurning.CreateConfig(0.5, 400, 1)

Pid = {}
function Pid.GetGain(self, I, name, obj, target, actual)
    value = target - actual

    -- P動作
    p = value * obj.current.kP

    -- I動作
    obj.total = obj.total + value
    table.insert(obj.logs, 1, value)
    c = table.maxn(obj.logs)

    while c > obj.current.Ti do
        obj.total = obj.total - obj.logs[c]
        table.remove(obj.logs, c)
        c = table.maxn(obj.logs)
    end  
    i = (obj.total / obj.current.Ti) * obj.current.kP

    -- D動作
    d = obj.current.Td * obj.current.kP

    return p + i + d
end

--------------------
-- オイラー角に変換
--------------------
function ToEulerAngle(deg)
  return deg / Mathf.PI * 180
end

--------------------
-- 0～360を-180～180に変換
--------------------
function ZeroOrigin(a)
  if a == 0 then
    return 0
  end
  return ((a + 180) % 360) - 180
end

--------------------
-- 二つのベクトルのなす角
--------------------
function Angle(a, b)
  return math.deg(math.acos(Vector3.Dot(a, b) / (Vector3.Magnitude(a) * Vector3.Magnitude(b))))
end

--------------------
-- 範囲内にあるかどうか
--------------------
function InRange(value, min, max)
  return min <= value and value <= max
end

--------------------
-- ハードウェアに操作要求
--------------------
function RequestControl(I, me, request)
  for index = 0, I:Component_GetCount(8) - 1, 1 do
    local info = I:Component_GetBlockInfo(8, index)
    
    if 1 == info.LocalForwards.y then
      -- AI hook
      -- 上向き水中翼はAI操作検知用

    elseif 1 == info.LocalForwards.z and 0 == info.LocalForwards.x  then
      -- 前向き水中翼でピッチ、ロール、高度を制御
      local pr = 0
      local pp = 0
      local pa = request.again
  
      if info.LocalPositionRelativeToCom.z > 0 then
        pp = -request.pgain
      elseif info.LocalPositionRelativeToCom.z < 0 then
        pp = request.pgain
      end

      if info.LocalPositionRelativeToCom.x > 0 then
        pr = request.rgain
      elseif info.LocalPositionRelativeToCom.x < 0 then
        pr = -request.rgain
      end

      local ha = (pp + pr + pa)
      I:Component_SetFloatLogic(8, index, ha * me.isForwarding)
    end
  end

end
  
--------------------
-- 操作指示の取得
--------------------
function GetControlRequest(I, me, tpi, forwardDrive, followTarget)
  local ret = {}
  --local steer = 0 -- 0 = steady, 1 = right, -1 = left

  local needRoll = 0
  local needPitch = 0
  ret.forwardDrive = forwardDrive
  ret.steer = 0

  ret.pgain = Pid:GetGain(I, "PITCH", ppid, needPitch, me.pitch)
  ret.rgain = Pid:GetGain(I, "ROLL", rpid, needRoll, me.roll)
  ret.again = Pid:GetGain(I, "ALT", apid, CRUISE_ALT, me.selfPos.y)

  return ret
end


--------------------
-- 
--------------------
function GetVehicleStatus(I)
  me = {}

  if I.Fleet.Members ~= nil and table.maxn(I.Fleet.Members) > 1 then
    local i=1
    while (I.Fleet.Members[i].CenterOfMass ~= me.com) do
     i=i+1
    end
  end

  me.info = I.Fleet.Members[i]
  me.selfPos = I:GetConstructPosition()
  me.com = I:GetConstructCenterOfMass()
  me.fvec = I:GetConstructForwardVector()
  me.rvec = I:GetConstructRightVector()
  me.uvec = I:GetConstructUpVector()
  me.vvec = I:GetVelocityVectorNormalized()
  me.fmag = I:GetForwardsVelocityMagnitude()
  me.pitch = ZeroOrigin(I:GetConstructPitch())
  me.roll = ZeroOrigin(I:GetConstructRoll())

  local a = Angle(me.vvec, me.fvec)
  if a < 45 then -- ?
    me.isForwarding = 1
  elseif a > 135 then
    me.isForwarding = -1
  else
    me.isForwarding = 0
  end
  return me
end

--------------------
-- From The Depths
--------------------
function Update(I)
  I:ClearLogs()
  local me = GetVehicleStatus(I)
  local request = {forwardDrive = 0, steer = 0, pgain = 0, rgain = 0, again = 0}

  request = GetControlRequest(I, me, tpi, forwardDrive)

  if I.AIMode == "patrol" or I.AIMode == "combat" or I.AIMode == "on" then
    RequestControl(I, me, request, followTarget)
  else
    request.steer = 0
    request.forwardDrive = 0
    RequestControl(I, me, request, followTarget)
  end

end
