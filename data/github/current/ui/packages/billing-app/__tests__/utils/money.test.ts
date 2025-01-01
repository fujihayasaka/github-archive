import {formatMoneyDisplay} from '../../utils/money'

describe('formatMoneyDisplay', () => {
  it('formats amounts less than one cent correctly when digits argument is 2', () => {
    expect(formatMoneyDisplay(0.008, 2)).toBe('<$0.01')
    expect(formatMoneyDisplay(0.002, 2)).toBe('<$0.01')
  })

  it('formats amounts less than one cent correctly when digits argument is greater than 2', () => {
    expect(formatMoneyDisplay(0.008, 3)).toBe('$0.008')
    expect(formatMoneyDisplay(0.00009, 5)).toBe('$0.00009')
  })

  it('formats numbers correctly when using the default digits argument', () => {
    expect(formatMoneyDisplay(11.11111)).toBe('$11.11')
    expect(formatMoneyDisplay(11)).toBe('$11.00')
  })

  it('formats zero correctly when forceFormattingForZero is true', () => {
    expect(formatMoneyDisplay(0, 2, true)).toBe('$0.00')
  })

  it('formats zero to $0 regardless of decimal places provided when forceFormattingForZero is false', () => {
    expect(formatMoneyDisplay(0, 2, false)).toBe('$0')
  })

  it('formats zero to the provided number of decimal places when forceFormattingForZero is true', () => {
    expect(formatMoneyDisplay(0, 2, true)).toBe('$0.00')
  })

  it('does not add decimal places if the digits argument is greater than the decimal places in the amount', () => {
    expect(formatMoneyDisplay(0.11, 5)).toBe('$0.11')
  })
})
