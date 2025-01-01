import {generateSuggestedBranchName} from '../utils'

describe('generateSuggestedBranchName', () => {
  test('turns the current issue number and title into a potential branch name', () => {
    expect(generateSuggestedBranchName(123, 'This is a title')).toBe('123-this-is-a-title')
  })

  test('includes numbers in the title', () => {
    expect(generateSuggestedBranchName(123, 'This is a 42 title')).toBe('123-this-is-a-42-title')
  })

  test('strips emojis', () => {
    expect(generateSuggestedBranchName(123, 'This is a 🎃 title')).toBe('123-this-is-a-title')
  })

  test('strips all punctuation and brackets', () => {
    expect(generateSuggestedBranchName(123, '[some epic] This... /(is)/ & {a} <> title...')).toBe(
      '123-some-epic-this-is-a-title',
    )
  })

  test('strips all emoji and punctuation while preserving underscores and non-latin characters', () => {
    expect(
      generateSuggestedBranchName(
        123,
        '[some epic] ↕️ This is a _title_ with emoji 👍 👥 👍🏽 & non-latin characters like é!',
      ),
    ).toBe('123-some-epic-this-is-a-_title_-with-emoji-non-latin-characters-like-é')
  })

  test('strips single quotes', () => {
    expect(generateSuggestedBranchName(111, "This is a 'title'")).toBe('111-this-is-a-title')
  })

  test('strips double quotes', () => {
    expect(
      generateSuggestedBranchName(456, 'Create "Add Iteration" component and wire it up on the settings page'),
    ).toBe('456-create-add-iteration-component-and-wire-it-up-on-the-settings-page')
  })

  test('retains excessive -s in the middle', () => {
    expect(generateSuggestedBranchName(111, 'This----is a title')).toBe('111-this----is-a-title')
  })

  test('removes trailing or leading -s', () => {
    expect(generateSuggestedBranchName(111, '---This is a title---')).toBe('111-this-is-a-title')
  })

  test('removes non-printable characters', () => {
    expect(generateSuggestedBranchName(123, 'This is a title\u0000')).toBe('123-this-is-a-title')
  })

  test('removes variation selectors', () => {
    expect(generateSuggestedBranchName(123, 'This is a title\uFE0F')).toBe('123-this-is-a-title')
  })

  test('removes angle brackets', () => {
    expect(generateSuggestedBranchName(123, 'This is a <title>')).toBe('123-this-is-a-title')
  })

  test('removes Unicode C1 control characters', () => {
    expect(generateSuggestedBranchName(123, 'This is a title\u0080')).toBe('123-this-is-a-title')
  })

  test('removes special characters like ~, ^, :, ?, *, [, \\', () => {
    expect(generateSuggestedBranchName(123, 'This is a ~title^: ?* [\\')).toBe('123-this-is-a-title')
  })

  test('handles titles with only special characters', () => {
    expect(generateSuggestedBranchName(123, '~^:?*')).toBe('123-')
  })

  test('handles titles with leading and trailing spaces', () => {
    expect(generateSuggestedBranchName(123, '   This is a title   ')).toBe('123-this-is-a-title')
  })

  test('handles titles with multiple spaces between words', () => {
    expect(generateSuggestedBranchName(123, 'This    is    a    title')).toBe('123-this-is-a-title')
  })

  test('handles titles with mixed case', () => {
    expect(generateSuggestedBranchName(123, 'This Is A Title')).toBe('123-this-is-a-title')
  })

  test('handles titles with underscores', () => {
    expect(generateSuggestedBranchName(123, 'This_is_a_title')).toBe('123-this_is_a_title')
  })

  test('handles titles with emojis and skin tone modifiers', () => {
    expect(generateSuggestedBranchName(123, 'This is a title 👍🏽')).toBe('123-this-is-a-title')
  })

  test('handles titles with multiple underscores', () => {
    expect(generateSuggestedBranchName(123, 'This__is__a__title')).toBe('123-this__is__a__title')
  })

  test('handles titles with mixed punctuation', () => {
    expect(generateSuggestedBranchName(123, 'This is a title!@#$%^&*()')).toBe('123-this-is-a-title')
  })

  test('handles titles with non-printable characters', () => {
    expect(generateSuggestedBranchName(123, 'This is a title\u0001\u0002\u0003')).toBe('123-this-is-a-title')
  })

  test('handles titles with variation selectors', () => {
    expect(generateSuggestedBranchName(123, 'This is a title\uFE0F')).toBe('123-this-is-a-title')
  })

  test('handles titles with angle brackets', () => {
    expect(generateSuggestedBranchName(123, 'This is a <title>')).toBe('123-this-is-a-title')
  })

  test('handles titles with Unicode C1 control characters', () => {
    expect(generateSuggestedBranchName(123, 'This is a title\u0080')).toBe('123-this-is-a-title')
  })

  test('handles titles with special characters like ~, ^, :, ?, *, [, \\', () => {
    expect(generateSuggestedBranchName(123, 'This is a ~title^: ?* [\\')).toBe('123-this-is-a-title')
  })

  test('handles titles with multiple consecutive hyphens', () => {
    expect(generateSuggestedBranchName(123, 'This--is--a--title')).toBe('123-this--is--a--title')
  })

  test('handles titles with mixed language characters', () => {
    expect(generateSuggestedBranchName(123, 'This is a title with 中文 characters')).toBe(
      '123-this-is-a-title-with-中文-characters',
    )
  })

  test('handles titles with special characters and numbers', () => {
    expect(generateSuggestedBranchName(123, 'This is a title with special characters !@#$%^&*()123')).toBe(
      '123-this-is-a-title-with-special-characters-123',
    )
  })

  test('handles titles with only numbers', () => {
    expect(generateSuggestedBranchName(123, '1234567890')).toBe('123-1234567890')
  })

  test('postfixes a number if the branch name is taken', () => {
    const repo = new Set(['123-this-is-a-title', '123-this-is-a-title-1'])
    expect(generateSuggestedBranchName(123, 'This is a title', repo)).toBe('123-this-is-a-title-2')
  })
})
