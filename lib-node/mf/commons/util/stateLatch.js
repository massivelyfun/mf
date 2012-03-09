(function() {
  var StateLatch, mf;

  mf = require("mf");

  StateLatch = (function() {

    function StateLatch(taskManager, evts, onAllFiredCb) {
      var evt, _i, _len;
      this._taskManager = taskManager != null ? taskManager : mf.core.taskManager();
      this._firedEvents = {};
      this._allowedEvents = evts != null ? evts : [];
      this._done = false;
      for (_i = 0, _len = evts.length; _i < _len; _i++) {
        evt = evts[_i];
        this._firedEvents[evt] = false;
      }
      this._onAllFiredCb = onAllFiredCb != null ? onAllFiredCb : (function() {});
      if (evts.length < 1) {
        this._allFired();
        this._taskManager.runTask(this._onAllFiredCb);
      }
    }

    StateLatch.prototype.record = function(evt) {
      var ret;
      ret = false;
      if (this._allowedEvents.indexOf(evt) >= 0) {
        this._firedEvents[evt] = true;
        ret = true;
        this.checkAllFired();
      }
      return ret;
    };

    StateLatch.prototype.checkAllFired = function() {
      var k, v, _ref;
      _ref = this._firedEvents;
      for (k in _ref) {
        v = _ref[k];
        if (!v) return;
      }
      return this._allFired();
    };

    StateLatch.prototype._allFired = function() {
      this._done = true;
      return this._taskManager.runTaskFast(this._onAllFiredCb);
    };

    StateLatch.prototype.done = function() {
      return this._done;
    };

    StateLatch.prototype.getTrigger = function(state) {
      var _this = this;
      return (function() {
        return _this.record(state);
      });
    };

    return StateLatch;

  })();

  module.exports = StateLatch;

}).call(this);
