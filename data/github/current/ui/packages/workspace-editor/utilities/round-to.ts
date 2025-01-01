// Utility to round a number to a specified number of digits after the decimal point.
export function roundTo(numberToRound: number, digitsCount: number): number {
  return Number(numberToRound.toFixed(digitsCount))
}
