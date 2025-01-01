import {checkConditionalAllowedPaths} from '../helpers'

test('checkConditionalAllowedPaths none match', () => {
  let result = checkConditionalAllowedPaths('foo', ['repository', 'discussion'])
  expect(result).toBe(false)

  result = checkConditionalAllowedPaths('NOT_FOUND', [1, 0])
  expect(result).toBe(false)
})

test('checkConditionalAllowedPaths match', () => {
  const result = checkConditionalAllowedPaths('NOT_FOUND', ['repository', 'discussion'])
  expect(result).toBe(true)
})

test('checkConditionalAllowedPaths match with wildcards', () => {
  let result = checkConditionalAllowedPaths('NOT_FOUND', [
    'repository',
    'issue',
    'frontTimelineItems',
    'edges',
    5,
    'node',
    'commit',
    'signature',
    'signer',
  ])
  expect(result).toBe(true)

  result = checkConditionalAllowedPaths('NOT_FOUND', [
    'repository',
    'issue',
    'backTimelineItems',
    'edges',
    0,
    'node',
    'commit',
    'signature',
    'signer',
  ])
  expect(result).toBe(true)
})
