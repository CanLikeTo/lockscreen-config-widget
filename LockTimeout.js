.pragma library

var DEFAULT_LOCK_SECONDS = 300
var UNAVAILABLE = "Shell configuration unavailable."

function secondsFromConfig(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function isVersion1Object(parsed) {
  return parsed && typeof parsed === "object" && !Array.isArray(parsed) && parsed.version === 1
}

function textOf(value) {
  return value === undefined || value === null ? "" : String(value)
}

function parseShell(text) {
  var raw = textOf(text)
  if (!raw.trim()) return null
  try {
    var parsed = JSON.parse(raw)
    if (!isVersion1Object(parsed)) return null
    if (Object.prototype.hasOwnProperty.call(parsed, "idle") && !isPlainObject(parsed.idle)) return null
    return parsed
  } catch (error) {
    return null
  }
}

function lockSnapshot(config) {
  var idleExisted = isPlainObject(config.idle)
  var lockExisted = idleExisted && Object.prototype.hasOwnProperty.call(config.idle, "lock")
  return {
    idleExisted: idleExisted,
    lockExisted: lockExisted,
    seconds: lockExisted
      ? secondsFromConfig(config.idle.lock, DEFAULT_LOCK_SECONDS)
      : DEFAULT_LOCK_SECONDS
  }
}

function isChoice(choice) {
  return choice === "default" || choice === "300" || choice === "600"
}

function choiceSeconds(choice) {
  if (choice === "600") return 600
  if (choice === "300") return 300
  return -1
}

function fileMatchesChoice(config, choice) {
  var seconds = choiceSeconds(choice)
  if (seconds < 0 || !isPlainObject(config) || !isPlainObject(config.idle)) return false
  if (!Object.prototype.hasOwnProperty.call(config.idle, "lock")) return false
  var raw = config.idle.lock
  return typeof raw === "number" && isFinite(raw) && raw === seconds
}

function cloneConfig(config) {
  return JSON.parse(JSON.stringify(config))
}

function isEmptyObject(value) {
  if (!isPlainObject(value)) return false
  for (var key in value) {
    if (Object.prototype.hasOwnProperty.call(value, key)) return false
  }
  return true
}

function withLock(config, seconds) {
  var next = cloneConfig(config)
  if (!isPlainObject(next.idle)) next.idle = {}
  next.idle.lock = seconds
  return next
}

function withoutLock(config, removeIdleIfEmpty) {
  var next = cloneConfig(config)
  if (isPlainObject(next.idle) && Object.prototype.hasOwnProperty.call(next.idle, "lock"))
    delete next.idle.lock
  if (removeIdleIfEmpty && isEmptyObject(next.idle)) delete next.idle
  return next
}

function serialize(config) {
  return JSON.stringify(config, null, 2) + "\n"
}

function serializeState(state) {
  if (!state || state.owned !== true) return ""
  return JSON.stringify({
    owned: true,
    choice: state.choice,
    lockExisted: state.lockExisted === true,
    idleExisted: state.idleExisted === true,
    originalSeconds: state.originalSeconds
  }, null, 2) + "\n"
}

function parseState(text) {
  var raw = textOf(text)
  if (!raw.trim()) return null
  try {
    var parsed = JSON.parse(raw)
    if (!isPlainObject(parsed) || parsed.owned !== true) return null
    if (parsed.choice !== "300" && parsed.choice !== "600") return null
    if (typeof parsed.lockExisted !== "boolean") return null
    if (typeof parsed.idleExisted !== "boolean") return null
    if (typeof parsed.originalSeconds !== "number" || !isFinite(parsed.originalSeconds) || parsed.originalSeconds < 0)
      return null
    return {
      owned: true,
      choice: parsed.choice,
      lockExisted: parsed.lockExisted,
      idleExisted: parsed.idleExisted,
      originalSeconds: Math.floor(parsed.originalSeconds)
    }
  } catch (error) {
    return null
  }
}

function ownedMemory(memory) {
  return memory && memory.owned === true ? memory : null
}

function decision(ok, choice, memory, actions, canSelect, statusText, configured, effective) {
  return {
    ok: ok,
    choice: choice,
    memory: memory || null,
    actions: actions || [],
    canSelect: !!canSelect,
    statusText: canSelect ? "" : (statusText || UNAVAILABLE),
    configuredLockSeconds: configured,
    effectiveLockSeconds: effective
  }
}

function unavailable(choice, memory, configured, effective) {
  return decision(false, choice || "default", memory, [], false, UNAVAILABLE, configured, effective)
}

function inspect(shellText) {
  var config = parseShell(shellText)
  if (!config) return unavailable("default", null, DEFAULT_LOCK_SECONDS, DEFAULT_LOCK_SECONDS)
  var info = lockSnapshot(config)
  return decision(true, "default", null, [], true, "", info.seconds, info.seconds)
}

function memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds) {
  if (!owned || (choice !== "300" && choice !== "600")) return null
  return {
    owned: true,
    choice: choice,
    lockExisted: !!lockExisted,
    idleExisted: !!idleExisted,
    originalSeconds: originalSeconds
  }
}

function selectFields(shellText, owned, choice, lockExisted, idleExisted, originalSeconds, nextChoice) {
  return select(shellText, memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds), nextChoice)
}

function reconcileFields(shellText, owned, choice, lockExisted, idleExisted, originalSeconds) {
  return reconcile(shellText, memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds))
}

function recoverFields(shellText, owned, choice, lockExisted, idleExisted, originalSeconds) {
  var memory = memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds)
  return recover(shellText, serializeState(memory))
}



function snapshotFor(memory, config) {
  if (memory) {
    return {
      lockExisted: memory.lockExisted === true,
      idleExisted: memory.idleExisted === true,
      originalSeconds: memory.originalSeconds
    }
  }
  var info = lockSnapshot(config)
  return {
    lockExisted: info.lockExisted,
    idleExisted: info.idleExisted,
    originalSeconds: info.seconds
  }
}

function restoredConfig(config, snapshot) {
  if (snapshot.lockExisted) return withLock(config, snapshot.originalSeconds)
  return withoutLock(config, snapshot.idleExisted !== true)
}

function select(shellText, memory, nextChoice) {
  var owned = ownedMemory(memory)
  var config = parseShell(shellText)
  if (!config) {
    var missingConfigured = owned ? owned.originalSeconds : DEFAULT_LOCK_SECONDS
    var missingEffective = owned ? choiceSeconds(owned.choice) : missingConfigured
    return unavailable(owned ? owned.choice : "default", owned, missingConfigured, missingEffective)
  }

  var info = lockSnapshot(config)
  if (!isChoice(nextChoice)) {
    if (owned && !fileMatchesChoice(config, owned.choice)) {
      return decision(false, "default", null, [{ type: "clearState" }], true, "", info.seconds, info.seconds)
    }
    var keptConfigured = owned ? owned.originalSeconds : info.seconds
    var keptEffective = owned ? choiceSeconds(owned.choice) : info.seconds
    return decision(false, owned ? owned.choice : "default", owned, [], true, "", keptConfigured, keptEffective)
  }

  if (owned && !fileMatchesChoice(config, owned.choice)) {
    if (nextChoice !== "300" && nextChoice !== "600") {
      return decision(nextChoice === "default", "default", null, [{ type: "clearState" }], true, "", info.seconds, info.seconds)
    }
    owned = null
  }

  var snapshot = snapshotFor(owned, config)
  if (nextChoice === "default") {
    if (!owned) {
      return decision(true, "default", null, [], true, "", info.seconds, info.seconds)
    }
    return decision(true, "default", null, [
      { type: "writeShell", text: serialize(restoredConfig(config, snapshot)) },
      { type: "clearState" }
    ], true, "", snapshot.originalSeconds, snapshot.originalSeconds)
  }

  var nextMemory = {
    owned: true,
    choice: nextChoice,
    lockExisted: snapshot.lockExisted,
    idleExisted: snapshot.idleExisted,
    originalSeconds: snapshot.originalSeconds
  }
  return decision(true, nextChoice, nextMemory, [
    { type: "writeState", text: serializeState(nextMemory) },
    { type: "writeShell", text: serialize(withLock(config, choiceSeconds(nextChoice))) }
  ], true, "", snapshot.originalSeconds, choiceSeconds(nextChoice))
}

function reconcile(shellText, memory) {
  var owned = ownedMemory(memory)
  var config = parseShell(shellText)
  if (owned) {
    // A missing or partial read, including an atomic replace, is not a foreign edit.
    if (!config) {
      return decision(true, owned.choice, owned, [], false, UNAVAILABLE, owned.originalSeconds, choiceSeconds(owned.choice))
    }
    if (fileMatchesChoice(config, owned.choice)) {
      return decision(true, owned.choice, owned, [], true, "", owned.originalSeconds, choiceSeconds(owned.choice))
    }
    var foreign = lockSnapshot(config)
    return decision(true, "default", null, [{ type: "clearState" }], true, "", foreign.seconds, foreign.seconds)
  }
  if (!config) return unavailable("default", null, DEFAULT_LOCK_SECONDS, DEFAULT_LOCK_SECONDS)
  var info = lockSnapshot(config)
  return decision(true, "default", null, [], true, "", info.seconds, info.seconds)
}

function recover(shellText, stateText) {
  var raw = textOf(stateText)
  var state = parseState(raw)
  var config = parseShell(shellText)
  if (!state) {
    var view = inspect(shellText)
    view.ok = true
    view.actions = raw.trim() ? [{ type: "clearState" }] : []
    return view
  }
  if (!config) {
    // Do not create or overwrite an unusable user file. Leave state for a later start.
    return unavailable("default", null, state.originalSeconds, state.originalSeconds)
  }
  if (fileMatchesChoice(config, state.choice)) {
    var snapshot = snapshotFor(state, config)
    return decision(true, "default", null, [
      { type: "writeShell", text: serialize(restoredConfig(config, snapshot)) },
      { type: "clearState" }
    ], true, "", snapshot.originalSeconds, snapshot.originalSeconds)
  }
  var info = lockSnapshot(config)
  return decision(true, "default", null, [{ type: "clearState" }], true, "", info.seconds, info.seconds)
}
