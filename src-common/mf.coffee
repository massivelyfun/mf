Logger = require "mf-jack"
Log = Logger.create "mf"
ComponentLoader = require "./commons/util/componentLoader"

# # MfExecuctionContextDetector
# 
# Attempts to "sniff out" the current execution context,
# which, among other things, informs mf.core components
# about which components to load based on the platform's
# capabilities.

class MfExecutionContextDetector

  # # MfExecutionContextDetector::MfExecuctionContext
  # 
  # This dummy/base context should be treated as abstract.
  # It's mostly here to inform authors of other contexts
  # what the method interfaces should look like.
  class MfExecutionContext
    testMode: ->
      MF_TEST?
    name: ->
      throw "Default base MFExecutionContext has no name"

  # # MfExecutionContextDetector::WebExecutionContext
  # 
  # Implies that the current code is running in a browser.
  class WebExecutionContext extends MfExecutionContext
    name: ->
      "web"

  # # MfExecutionContextDetector::NodeExecutionContext
  # Implies that the current code is running in node
  class NodeExecutionContext extends MfExecutionContext
    name: ->
      "node"

  # ## hasGlobalOverride
  # 
  # @returns Whether or not the a global EXECUTION_CONTEXT has been
  # set.  This will override default context sniffing.
  hasGlobalOverride: ->
    EXECUTION_CONTEXT?
    
  # ## hasExportsObject
  # 
  # @returns whether or not the current scope defines an "exports"
  # object.  Given that this object has special meaning in node, it's
  # the primary method of detecting that the current code is running
  # in node.
  hasExportsObject: ->
    exports?
  
  # ## hasWindowObject  
  hasWindowObject: ->
    window?

  # ## detect
  # 
  # @returns a "best guess" for the current execution context (node,
  # web, etc)
  detect: ->
    # If someone's set a global override, merely return it
    return EXECUTION_CONTEXT if EXECUTION_CONTEXT?
    # If someone's set a test override, merely return it
    if MF_TEST? and MF_TEST_CONFIG? && MF_TEST_CONFIG.EXECUTION_CONTEXT?
      return MF_TEST_CONFIG.EXECUTION_CONTEXT

    # For now, do dumb detection
    if @hasWindowObject()
      return new WebExecutionContext()
    else
      return new NodeExecutionContext()


# ## MfExecuctionContextDetector#default
# @returns a context detector.
MfExecutionContextDetector::default = ->
  @_detector ||= new MfExecutionContextDetector()

# # Mf
#
# Mf is the root namespace, and contains useful runtime metadata
# (execution context and the like)
class Mf
  constructor: (executionContext) ->
    @executionContext = executionContext
    
  context: ->
    @executionContext

# # MfCore
#
# Utility methods.
class MfCore
  constructor: (mf) ->
    @mf = mf
    @klasses = {}
    @sequencers = {}
    @onces = {}

  # ## shallowClone
  #
  # Shallow copy of an objects properties.
  shallowClone: (obj) ->
    newObj = {}
    newObj[k] = v for k,v of obj
    newObj

  # ## intEq
  #
  # Integer equality; shaves off non-int bits.
  intEq: (one, two) ->
    (one << 0) == (two << 0)

  # ## noop
  #
  # noop fn for callback refs.
  noop: ->

  # ## once
  #
  # Executes fn if it hasn't been executed yet.
  once: (token, fn) =>
    unless @onces[token]?
      @onces[token] = true
      try
        fn()
      catch e

  # ## registerKlass
  #
  # Track classes.      
  registerKlass: (key, klass) ->
    @klasses[key] = klass

  # ## getKlasses
  #
  # Return tracked classes
  getKlass: (key) ->
    return @klasses[key]

  # ## extend
  #
  # Extends obj with function properties from mixin.
  extend: (obj, mixin) ->
    # use the below for an ECMA 5 environment where you may run into object
    # property setters and getters.
    #
    # for key in Object.keys(mixin)
    #   Object.defineProperty obj, Object.getOwnPropertyDescriptor(mixin, key)
    
    # The straightforward approach will work in ECMA 3 environments.
    for name, method of mixin when typeof obj[name] != 'function'
      obj[name] = method
    obj

  # ## runIf
  # 
  # Runs the specified fn if cond evaluates to true
  # Returns the result of fn if executed, else returns nothing
  runIf: (cond, fn) ->
    if typeof cond == "function"
      cond = cond()
    fn() if cond

  # ## taskManager
  # 
  # Returns a new task manager with the provided name.
  # If no name is given, the global task manager is returned.
  taskManager: (name) ->
    if name?
      new MfTaskManager(name)
    else
      MfTaskManager::global()

  # ## noifitcationCenter
  # 
  # Returns a new MfNotificationCenter using the provided MfTaskManager.
  # If no MfTaskManager is provided, the global MfNotificationCenter will
  # be returned, which uses the global MfTaskManager
  notificationCenter: (taskManager) ->
    if taskManager?
      new MfNotificationCenter(taskManager)
    else
      MfNotificationCenter::global()

  # ## MfSequencer
  # 
  # Returns an MfSequencer for the provided name. If no such sequencer exists,
  # it will be created and returned the next time said sequencer is requested.
  # If no name is provided, a new, anonymous sequencer will be returned.
  sequencer: (name) ->
    if name?
      if @sequencers[name]?
        @sequencers[name]
      else
        @sequencers[name] = new MfSequencer
        @sequencers[name]
    else
      new MfSequencer()
      
  klassId: (note = "") ->
    "klass[#{note}]-#{@sequencer('klass').advance()}"
    
  instanceId: (klassId) ->
    "#{klassId}-i-#{@sequencer(klassId).advance()}"

# Wire it all up
mf = new Mf(MfExecutionContextDetector::default().detect())
mf.core = new MfCore(mf)

# If we have additional libs, attempt to load them directly if in node mode
require("./messages") mf:mf
require("./serialization") mf:mf

# ---
# ADDITIONAL CORE FUNCTIONALITY
# ---

# # MfTaskManager
# 
# Rather than have a bunch of ad-hoc setTimeouts, we have named task
# managers which (will eventually) track the tasks they've been tasked
# to run.  This should make event state easier to track.
class MfTaskManager
  constructor: (name) ->
    @name = name
    @scheduledTasks = []
    @periodTasks = {}
    @canTick = (process? and process.nextTick?)

  # ## wrapWithHandler
  #
  # Task wrapper which properly logs errors.    
  wrapWithHandler: (task) ->
    ->
      try
        task()
      catch error
        console.log error.stack if error.stack?
        console.log error

        Log.error error.stack if error.stack?
        Log.error error

  # ## runTask
  # 
  # If process and process.nextTick are defined, runs the task two
  # ticks from now, else, waits until "after" ms to run the task (via
  # setTimeout)
  runTask: (task, after) ->
    return unless task
    wrapped = @wrapWithHandler(task)
    if @canTick and not after?
      # Just wait two ticks
      process.nextTick ->
        process.nextTick wrapped
    else
      after ?= 20
      setTimeout wrapped, after

  # ## runTaskFast
  # 
  # If process and process.nextTick are defined, runs the task in the next tick,
  # else, runs the task 4 ms from now via setTimeout
  runTaskFast: (task) ->
    return unless task
    if @canTick
      # Next tick
      wrapped = @wrapWithHandler(task)
      process.nextTick wrapped
    else
      @runTask(task, 4)

  # ## runTaskNow
  # 
  # runTaskNow tries to execute the task as quickly as the browser
  # supports. In most browsers this will be ~10-15 ms, but can be as
  # low as ~2-4 ms in Chrome.  Note we can't set this to zero. It
  # causes an assertion error in Node.
  runTaskNow: (task) ->
    @runTask(task, 1)

  # ## scheduleTask
  scheduleTask: (task, every = 1000) ->
    # Again, make it dumb.
    @scheduledTasks.push [task, setInterval(task, every)]
    task

  # ## cancelTask
  cancelTask: (task) ->
    id = (t[1] for t in @scheduledTasks when t[0] == task)
    if id? && id[0]?
      clearInterval id[0]
    task

  # ## ticker
  # 
  # Returns a function that will (maybe) run funs passed to it
  # in the next tick.
  ticker: ->
    self = @
    (fn) ->
      if fn?
        self.runTaskFast fn

  # ## delayer
  delayer: ->
    tick = @ticker()
    (fn) ->
      (args...) ->
        tick ->
          fn args...

MfTaskManager::global = ->
  @_taskManager ||= new MfTaskManager("global")


# # MfNotificationCenter
# 
# A low-level mechanism for pub/sub
class MfNotificationCenter
  # # MfNotificationCenter::ActionScubsription
  class ActionSubscription
    constructor: (subject, action, fn) ->
      @subject = subject
      @action = action
      @fn = fn
      
    cancel: ->
      @subject._internalCancel(this)
      
  # # MfNotificationCenter::Subject
  class Subject
    constructor: (obj) ->
      @target = obj
      @potentialActions = []
      @subscriptions = {}
      
    subscribe: (action, fn) ->
      @subscriptions[action] ||= []
      sub = new ActionSubscription(this, action, fn)
      @subscriptions[action].push(sub)
      # Return the subscription, so the user can optionally
      # cancel it directly
      sub

    # Private - enables canceling from a subscription
    _internalCancel: (actionSubscription) ->
      @subscriptions[actionSubscription.action] =
        (sub for sub in @subscriptions[actionSubscription.action] when sub != actionSubscription)
      actionSubscription.fn
      
    cancel: (action, fn) ->
      @subscriptions[action] ||= []
      for actionSub in @subscriptions[action] when actionSub.fn == fn
        @_internalCancel(actionSub)

    notify: (taskManager, action, additionalArgs) ->
      # Don't bother looping if nobody has ever shown interest
      return unless @subscriptions[action]?
      # Loop through any subscribers listening for this action, notify
      for subscription in @subscriptions[action]
        do (subscription) ->
          taskManager.runTaskFast (-> subscription.fn(additionalArgs))


  constructor: (taskManager) ->
    @taskManager = taskManager
    @subjects = []
    
  _subjectForObject: (obj) ->
    found = (sub for sub in @subjects when sub.target == obj)
    return found[0] if found? and found.length > 0
    subject = new Subject(obj)
    @subjects.push(subject)
    subject
    
  subscribe: (obj, action, fn) ->
    sub = @_subjectForObject obj
    sub.subscribe(action, fn) if sub?

  # Usually called by the subject
  notify: (obj, action, additionalArgs...) ->
    sub = @_subjectForObject obj
    sub.notify(@taskManager, action, additionalArgs)
    
  cancel: (obj, action, fn) ->
    sub = @_subjectForObject(obj)
    sub.cancel(action, fn) if sub?

MfNotificationCenter::global = ->
  @_notificationCenter ||= new MfNotificationCenter(MfTaskManager::global())


# # MfSequencer
# 
# Advances ever upwards...
class MfSequencer
  constructor: ->
    @val = 0
    
  advance: ->
    @val++
    
  reset: ->
    @val = 0

# If we're in test mode, register some klasses for outside
# instantiation (but without exporting) This aids in unit testing
# internal components without making them public
if mf.context().testMode()
  mf.core.registerKlass "MfExecutionContextDetector", MfExecutionContextDetector

# Binds componentLoader.component to mf.component
componentLoader = new ComponentLoader(require, mf)

componentLoader.registerShortcut "commons/geometry", "geometry"
componentLoader.registerShortcut "commons/util/configuration", "configuration"
componentLoader.registerShortcut "commons/util/componentLoader", "componentLoader"
componentLoader.registerShortcut "commons/util/configurationBuilder", "configurationBuilder"
componentLoader.registerShortcut "commons/util/stateLatch", "stateLatch"
componentLoader.registerShortcut "commons/util/countdownLatch", "countdownLatch"
componentLoader.registerShortcut "commons/util/stateGuard", "stateGuard"
componentLoader.registerShortcut "commons/util/uuid", "uuid"
componentLoader.registerShortcut "commons/util/configurationSource", "configurationSource"
componentLoader.registerShortcut "commons/util/rawConfiguration", "rawConfiguration"
componentLoader.registerShortcut "commons/util/defaultingConfiguration", "defaultingConfiguration"
componentLoader.registerShortcut "commons/collection/hashtable", "hashtable"
componentLoader.registerShortcut "commons/collection/hashSet", "hashSet"
componentLoader.registerShortcut "commons/util/keyPair", "keyPair"

module.exports = mf
