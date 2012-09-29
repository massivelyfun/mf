(function() {
  var FourBitPacker;

  FourBitPacker = (function() {

    function FourBitPacker() {}

    FourBitPacker.prototype.encode = function(tileAr) {
      var outputString, tile, workingInt, _i, _len;
      outputString = "";
      for (_i = 0, _len = tileAr.length; _i < _len; _i++) {
        tile = tileAr[_i];
        tile &= 0x0f;
        if (workingInt) {
          workingInt |= tile;
          outputString += String.fromCharCode(workingInt);
          workingInt = void 0;
        } else {
          workingInt = tile << 4;
        }
      }
      if (workingInt) outputString += String.fromCharCode(workingInt |= 0xf00);
      return outputString;
    };

    FourBitPacker.prototype.decode = function(tileStr) {
      var code, i, tileAr;
      tileAr = [];
      i = 0;
      while (i < tileStr.length) {
        code = tileStr.charCodeAt(i);
        if ((code & 0xf00) === 0xf00) {
          tileAr.push((code & 0x0f0) >> 4);
        } else {
          tileAr.push((code & 0xf0) >> 4);
          tileAr.push(code & 0x0f);
        }
        ++i;
      }
      return tileAr;
    };

    return FourBitPacker;

  })();

  module.exports = FourBitPacker;

}).call(this);
