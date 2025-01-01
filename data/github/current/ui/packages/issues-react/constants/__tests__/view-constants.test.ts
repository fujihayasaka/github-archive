import {CUSTOM_VIEW} from '../view-constants'

describe('CUSTOM_VIEW.query', () => {
  test('returns author query for author parameter', () => {
    const result = CUSTOM_VIEW.query({author: 'octocat'})
    expect(result).toBe('author:octocat')
  })

  test('returns app author query for author parameter with createdByApp flag', () => {
    const result = CUSTOM_VIEW.query({author: 'myapp', createdByApp: true})
    expect(result).toBe('author:app/myapp')
  })

  test('returns assignee query for assignee parameter', () => {
    const result = CUSTOM_VIEW.query({assignee: 'octocat'})
    expect(result).toBe('assignee:octocat')
  })

  test('returns mentions query for mentioned parameter', () => {
    const result = CUSTOM_VIEW.query({mentioned: 'octocat'})
    expect(result).toBe('mentions:octocat')
  })

  test('returns label query for label parameter', () => {
    const result = CUSTOM_VIEW.query({label: 'bug'})
    expect(result).toBe('label:bug')
  })

  test('returns label query for label with special characters', () => {
    const result = CUSTOM_VIEW.query({label: 'needs-review'})
    expect(result).toBe('label:needs-review')
  })

  test('returns label query for label with dots and underscores', () => {
    const result = CUSTOM_VIEW.query({label: 'priority.high_urgent'})
    expect(result).toBe('label:priority.high_urgent')
  })

  test('returns undefined when no parameters are provided', () => {
    const result = CUSTOM_VIEW.query({})
    expect(result).toBeUndefined()
  })

  test('prioritizes author over other parameters when multiple are provided', () => {
    const result = CUSTOM_VIEW.query({author: 'octocat', assignee: 'user2', label: 'bug'})
    expect(result).toBe('author:octocat')
  })

  test('prioritizes assignee over mentioned and label when author is not provided', () => {
    const result = CUSTOM_VIEW.query({assignee: 'octocat', mentioned: 'user2', label: 'bug'})
    expect(result).toBe('assignee:octocat')
  })

  test('prioritizes mentioned over label when author and assignee are not provided', () => {
    const result = CUSTOM_VIEW.query({mentioned: 'octocat', label: 'bug'})
    expect(result).toBe('mentions:octocat')
  })
})
