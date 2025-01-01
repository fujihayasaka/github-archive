// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {roundTo} from '../round-to'

describe('`roundTo` utility', () => {
  test('roundsTo up 1 digits', () => {
    const num = 2.4576

    expect(roundTo(num, 1)).toBe(2.5)
  })

  test('roundsTo down 1 digits', () => {
    const num = 2.4424

    expect(roundTo(num, 1)).toBe(2.4)
  })

  test('roundsTo up 2 digits', () => {
    const num = 2.4576

    expect(roundTo(num, 2)).toBe(2.46)
  })

  test('roundsTo down 2 digits', () => {
    const num = 2.4524

    expect(roundTo(num, 2)).toBe(2.45)
  })

  test('roundsTo up 3 digits', () => {
    const num = 2.4576

    expect(roundTo(num, 3)).toBe(2.458)
  })

  test('roundsTo down 3 digits', () => {
    const num = 2.4524

    expect(roundTo(num, 3)).toBe(2.452)
  })
})
