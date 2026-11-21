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
  // Keep the JSON value. Normalized seconds are for display only.
  var rawLock = lockExisted ? config.idle.lock : undefined
  return {
    idleExisted: idleExisted,
    lockExisted: lockExisted,
    seconds: lockExisted
      ? secondsFromConfig(rawLock, DEFAULT_LOCK_SECONDS)
      : DEFAULT_LOCK_SECONDS,
    rawLock: rawLock
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

function isDurationChoice(choice) {
  return choice === "300" || choice === "600"
}

function fileMatchesChoice(config, choice) {
  var seconds = choiceSeconds(choice)
  if (seconds < 0 || !isPlainObject(config) || !isPlainObject(config.idle)) return false
  if (!Object.prototype.hasOwnProperty.call(config.idle, "lock")) return false
  var raw = config.idle.lock
  return typeof raw === "number" && isFinite(raw) && raw === seconds
}

// A switch journal names both the override already on disk and the target of this write.
function fileMatchesJournal(config, state) {
  if (!state) return false
  if (fileMatchesChoice(config, state.choice)) return true
  if (fileMatchesChoice(config, state.pendingChoice)) return true
  if (fileMatchesChoice(config, state.appliedChoice)) return true
  return false
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

function withLock(config, value) {
  var next = cloneConfig(config)
  if (!isPlainObject(next.idle)) next.idle = {}
  next.idle.lock = value
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
  var record = {
    owned: true,
    choice: state.choice,
    lockExisted: state.lockExisted === true,
    idleExisted: state.idleExisted === true,
    originalSeconds: state.originalSeconds
  }
  if (isDurationChoice(state.appliedChoice)) record.appliedChoice = state.appliedChoice
  if (isDurationChoice(state.pendingChoice)) record.pendingChoice = state.pendingChoice
  // Include null. JSON.stringify keeps it; do not drop the key or pass it through Number().
  if (state.lockExisted === true && Object.prototype.hasOwnProperty.call(state, "originalLock"))
    record.originalLock = state.originalLock
  return JSON.stringify(record, null, 2) + "\n"
}

function takeDuration(parsed, key, state) {
  if (!Object.prototype.hasOwnProperty.call(parsed, key)) return true
  if (!isDurationChoice(parsed[key])) return false
  state[key] = parsed[key]
  return true
}

function parseState(text) {
  var raw = textOf(text)
  if (!raw.trim()) return null
  try {
    var parsed = JSON.parse(raw)
    if (!isPlainObject(parsed) || parsed.owned !== true) return null
    if (!isDurationChoice(parsed.choice)) return null
    if (typeof parsed.lockExisted !== "boolean") return null
    if (typeof parsed.idleExisted !== "boolean") return null
    if (typeof parsed.originalSeconds !== "number" || !isFinite(parsed.originalSeconds) || parsed.originalSeconds < 0)
      return null
    var state = {
      owned: true,
      choice: parsed.choice,
      lockExisted: parsed.lockExisted,
      idleExisted: parsed.idleExisted,
      originalSeconds: Math.floor(parsed.originalSeconds)
    }
    if (!takeDuration(parsed, "appliedChoice", state)) return null
    if (!takeDuration(parsed, "pendingChoice", state)) return null
    if (state.lockExisted && Object.prototype.hasOwnProperty.call(parsed, "originalLock"))
      state.originalLock = parsed.originalLock
    return state
  } catch (error) {
    return null
  }
}

function ownedMemory(memory) {
  return memory && memory.owned === true ? memory : null
}

function decision(ok, choice, memory, actions, canSelect, statusText, configured, effective, recoveryPending) {
  var hasOriginalLock = !!(memory && Object.prototype.hasOwnProperty.call(memory, "originalLock"))
  return {
    ok: ok,
    choice: choice,
    memory: memory || null,
    actions: actions || [],
    canSelect: !!canSelect && !recoveryPending,
    statusText: canSelect && !recoveryPending ? "" : (statusText || UNAVAILABLE),
    configuredLockSeconds: configured,
    effectiveLockSeconds: effective,
    recoveryPending: !!recoveryPending,
    hasOriginalLock: hasOriginalLock,
    originalLock: hasOriginalLock ? memory.originalLock : null
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

function memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds, originalLock, hasOriginalLock) {
  if (!owned || !isDurationChoice(choice)) return null
  var memory = {
    owned: true,
    choice: choice,
    lockExisted: !!lockExisted,
    idleExisted: !!idleExisted,
    originalSeconds: originalSeconds
  }
  // A var property can surface JSON null as undefined. The flag says the key was present.
  if (hasOriginalLock) memory.originalLock = originalLock === undefined ? null : originalLock
  return memory
}

function selectFields(shellText, owned, choice, lockExisted, idleExisted, originalSeconds, nextChoice, originalLock, hasOriginalLock) {
  return select(shellText, memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds, originalLock, hasOriginalLock), nextChoice)
}

function reconcileFields(shellText, owned, choice, lockExisted, idleExisted, originalSeconds, originalLock, hasOriginalLock) {
  return reconcile(shellText, memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds, originalLock, hasOriginalLock))
}

function recoverFields(shellText, owned, choice, lockExisted, idleExisted, originalSeconds, originalLock, hasOriginalLock) {
  var memory = memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds, originalLock, hasOriginalLock)
  return recover(shellText, serializeState(memory))
}

// Watcher entry. A pending journal must be recovered before choices enable.
function shellChanged(shellText, owned, choice, lockExisted, idleExisted, originalSeconds, originalLock, hasOriginalLock, recoveryPending, stateText) {
  if (recoveryPending) {
    if (!textOf(stateText).trim()) {
      var held = unavailable("default", null, originalSeconds, originalSeconds)
      held.recoveryPending = true
      held.canSelect = false
      return held
    }
    var resolved = recover(shellText, stateText)
    if (resolved.recoveryPending) resolved.canSelect = false
    return resolved
  }
  return reconcile(shellText, memoryFrom(owned, choice, lockExisted, idleExisted, originalSeconds, originalLock, hasOriginalLock))
}

function snapshotFor(memory, config) {
  if (memory) {
    var existed = memory.lockExisted === true
    var snap = {
      lockExisted: existed,
      idleExisted: memory.idleExisted === true,
      originalSeconds: memory.originalSeconds
    }
    if (existed) {
      snap.originalLock = Object.prototype.hasOwnProperty.call(memory, "originalLock")
        ? memory.originalLock
        : memory.originalSeconds
    }
    return snap
  }
  var info = lockSnapshot(config)
  var fresh = {
    lockExisted: info.lockExisted,
    idleExisted: info.idleExisted,
    originalSeconds: info.seconds
  }
  if (info.lockExisted) fresh.originalLock = info.rawLock
  return fresh
}

function restoredConfig(config, snapshot) {
  if (!snapshot.lockExisted) return withoutLock(config, snapshot.idleExisted !== true)
  var value = Object.prototype.hasOwnProperty.call(snapshot, "originalLock")
    ? snapshot.originalLock
    : snapshot.originalSeconds
  return withLock(config, value)
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
    pendingChoice: nextChoice,
    lockExisted: snapshot.lockExisted,
    idleExisted: snapshot.idleExisted,
    originalSeconds: snapshot.originalSeconds
  }
  // Only a previous override is applied. The original disk value is not.
  if (owned && isDurationChoice(owned.choice)) nextMemory.appliedChoice = owned.choice
  if (snapshot.lockExisted)
    nextMemory.originalLock = snapshot.originalLock
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
    var pending = unavailable("default", null, state.originalSeconds, state.originalSeconds)
    pending.recoveryPending = true
    pending.canSelect = false
    return pending
  }
  if (fileMatchesJournal(config, state)) {
    var snapshot = snapshotFor(state, config)
    return decision(true, "default", null, [
      { type: "writeShell", text: serialize(restoredConfig(config, snapshot)) },
      { type: "clearState" }
    ], true, "", snapshot.originalSeconds, snapshot.originalSeconds)
  }
  var info = lockSnapshot(config)
  return decision(true, "default", null, [{ type: "clearState" }], true, "", info.seconds, info.seconds)
}
