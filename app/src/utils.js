/**
 * Get the whole and decimal parts from a number.
 * Trims leading and trailing zeroes.
 *
 * @param {string} num the number
 * @returns {Array<string>} array with the [<whole>, <decimal>] parts of the number
 */
export function splitDecimalNumber(num) {
  const [whole = '', dec = ''] = num.split('.')
  return [
    whole.replace(/^0*/, ''), // trim leading zeroes
    dec.replace(/0*$/, ''), // trim trailing zeroes
  ]
}

/**
 * Format a decimal-based number back to a normal number
 *
 * @param {string} num the number
 * @param {number} decimals number of decimal places
 * @param {Object} [options] options object
 * @param {bool} [options.truncate=true] Should the number be truncated to its decimal base
 * @returns {string} formatted number
 */
export function fromDecimals(num, decimals, { truncate = true } = {}) {
  const [whole, dec] = splitDecimalNumber(num)
  if (!whole && !dec) {
    return '0'
  }

  const paddedWhole = whole.padStart(decimals + 1, '0')
  const decimalIndex = paddedWhole.length - decimals
  const wholeWithoutBase = paddedWhole.slice(0, decimalIndex)
  const decWithoutBase = paddedWhole.slice(decimalIndex)

  if (!truncate && dec) {
    // We need to keep all the zeroes in this case
    return `${wholeWithoutBase}.${decWithoutBase}${dec}`
  }

  // Trim any trailing zeroes from the new decimals
  const decWithoutBaseTrimmed = decWithoutBase.replace(/0*$/, '')
  if (decWithoutBaseTrimmed) {
    return `${wholeWithoutBase}.${decWithoutBaseTrimmed}`
  }

  return wholeWithoutBase
}

/**
 * Format the number to be in a given decimal base
 *
 * @param {string} num the number
 * @param {number} decimals number of decimal places
 * @param {Object} [options] options object
 * @param {bool} [options.truncate=true] Should the number be truncated to its decimal base
 * @returns {string} formatted number
 */
export function toDecimals(num, decimals, { truncate = true } = {}) {
  const [whole, dec] = splitDecimalNumber(num)
  if (!whole && (!dec || !decimals)) {
    return '0'
  }

  const wholeLengthWithBase = whole.length + decimals
  const withoutDecimals = (whole + dec).padEnd(wholeLengthWithBase, '0')
  const wholeWithBase = withoutDecimals.slice(0, wholeLengthWithBase)

  if (!truncate && wholeWithBase.length < withoutDecimals.length) {
    return `${wholeWithBase}.${withoutDecimals.slice(wholeLengthWithBase)}`
  }
  return wholeWithBase
}

/**
 * Format the balance to a fixed number of decimals
 *
 * @param {BN} amount the total amount
 * @param {BN} base the decimals base
 * @param {number} precision number of decimals to format
 * @return {string} formatted balance
 */
export function formatBalance(amount, base, precision = 2) {
  const baseLength = base.toString().length

  const whole = amount.div(base).toString()
  let fraction = amount.mod(base).toString()
  const zeros = '0'.repeat(Math.max(0, baseLength - fraction.length - 1))
  fraction = `${zeros}${fraction}`.replace(/0+$/, '').slice(0, precision)

  if (fraction === '' || parseInt(fraction, 10) === 0) {
    return whole
  }

  return `${whole}.${fraction}`
}
