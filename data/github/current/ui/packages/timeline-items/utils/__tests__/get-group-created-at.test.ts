import {getGroupCreatedAt} from '../get-group-created-at'

describe('getGroupCreatedAt', () => {
  test('returns default createdAt', () => {
    const createdAt = '2022-01-01'

    expect(getGroupCreatedAt(createdAt, [])).toBe('2022-01-01')
  })

  test('returns latest createdAt', () => {
    const createdAt = '2022-01-01'

    const group = [{createdAt: '2023-01-01'}, {createdAt: '2021-01-01'}]

    expect(getGroupCreatedAt(createdAt, group)).toBe(new Date('2023-01-01').valueOf())
  })
})
