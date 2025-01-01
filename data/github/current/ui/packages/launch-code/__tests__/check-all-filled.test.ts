import {checkAllFilled} from '../helpers/check-all-filled'

describe('checkAllFilled', () => {
  it('returns true when all inputs are filled', () => {
    const mockInputRefs = {
      current: [{value: '1'} as HTMLInputElement, {value: '2'} as HTMLInputElement, {value: '3'} as HTMLInputElement],
    }

    expect(checkAllFilled(mockInputRefs)).toBe(true)
  })

  it('returns false when at least one input is empty', () => {
    const mockInputRefs = {
      current: [{value: '1'} as HTMLInputElement, {value: ''} as HTMLInputElement, {value: '3'} as HTMLInputElement],
    }

    expect(checkAllFilled(mockInputRefs)).toBe(false)
  })

  it('returns false when all inputs are empty', () => {
    const mockInputRefs = {
      current: [{value: ''} as HTMLInputElement, {value: ''} as HTMLInputElement, {value: ''} as HTMLInputElement],
    }

    expect(checkAllFilled(mockInputRefs)).toBe(false)
  })

  it('handles leading/trailing whitespace correctly', () => {
    const mockInputRefs = {
      current: [{value: '  '} as HTMLInputElement, {value: '2'} as HTMLInputElement, {value: '3'} as HTMLInputElement],
    }

    expect(checkAllFilled(mockInputRefs)).toBe(false)
  })
})
