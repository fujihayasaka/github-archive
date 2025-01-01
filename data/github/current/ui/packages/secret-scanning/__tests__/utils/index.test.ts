import {toPercentInt} from '../../utils'

describe('toPercentInt', () => {
  it('handles divide by 0', () => {
    expect(toPercentInt(0, 0)).toBe(0)
  })

  it('rounds correctly', () => {
    expect(toPercentInt(50.5, 100)).toBe(51)
    expect(toPercentInt(50.49, 100)).toBe(50)
  })

  it('floors', () => {
    expect(toPercentInt(50.9, 100, {floor: true})).toBe(50)
  })
})
