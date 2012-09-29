class FourBitPacker
  encode: (tileAr) ->
    outputString = ""
    for tile in tileAr
      # this depends on being fed a 4-bit int. mask to make sure.
      tile &= 0x0f
      if workingInt
        # if we have a workingInt, we've already filled its top 4
        # bits. put this tile in the bottom 4.
        workingInt |= tile
        outputString += String.fromCharCode(workingInt)
        workingInt = undefined
      else
        # put this tile in the top 4 bits
        workingInt = (tile << 4)

    # special case: if the array is of odd length, we need to mark the
    # last character so we don't unpack an extra trailing zero. do this
    # by pushing into 12-bit characters
    if workingInt
      outputString += String.fromCharCode(workingInt |= 0xf00)

    outputString

  decode: (tileStr) ->
    tileAr = []
    i = 0
    while i < tileStr.length
      code = tileStr.charCodeAt(i)
      # if the this is a 12 bit character with the high order bits
      # set, we have an array with odd length, and we need to unpack
      # it a little differently.
      if (code & 0xf00) == 0xf00
         tileAr.push((code & 0x0f0) >> 4)
      else
        tileAr.push((code & 0xf0) >> 4)
        tileAr.push(code & 0x0f)
      ++i
    tileAr

module.exports = FourBitPacker
