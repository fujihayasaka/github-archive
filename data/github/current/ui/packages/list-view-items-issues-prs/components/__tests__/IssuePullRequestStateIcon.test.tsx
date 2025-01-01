import {getPullRequestEntityState} from '../IssuePullRequestStateIcon'

describe('#getPullRequestEntityState', () => {
  test('return open icon', () => {
    const openIcon = getPullRequestEntityState(false, false, 'OPEN')

    expect(openIcon).toBe('OPEN')
  })

  test('return draft icon', () => {
    const draftIcon = getPullRequestEntityState(true, false, 'OPEN')

    expect(draftIcon).toBe('DRAFT')
  })

  test('return closed icon', () => {
    const closedIcon = getPullRequestEntityState(false, false, 'CLOSED')

    expect(closedIcon).toBe('CLOSED')
  })

  test('return closed icon when closed draft', () => {
    const closedIcon = getPullRequestEntityState(true, false, 'CLOSED')

    expect(closedIcon).toBe('CLOSED')
  })

  test('return merged icon', () => {
    const mergedIcon = getPullRequestEntityState(false, false, 'MERGED')

    expect(mergedIcon).toBe('MERGED')
  })

  test('return merged icon when merged draft', () => {
    const mergedIcon = getPullRequestEntityState(true, false, 'MERGED')

    expect(mergedIcon).toBe('MERGED')
  })

  test('return merge queue icon', () => {
    const mergeQueueIcon = getPullRequestEntityState(false, true, 'OPEN')

    expect(mergeQueueIcon).toBe('IN_MERGE_QUEUE')
  })

  test('throws error when unknown state', () => {
    // eslint-disable-next-line relay/no-future-added-value -- Using a value the function will accept but ultimately throw an error
    const badState = '%future added value'
    expect(() => getPullRequestEntityState(false, false, badState)).toThrow(`Invalid pull request state: ${badState}`)
  })
})
