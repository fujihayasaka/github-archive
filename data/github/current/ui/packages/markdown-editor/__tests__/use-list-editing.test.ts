import {listItemToString, parseListItem} from '../use-list-editing'
import type {ListItem} from '../use-list-editing'
describe('parse list items', () => {
  test('should match a list item', () => {
    const line = '- [ ] item'
    const result = parseListItem(line)
    expect(result).toEqual({
      leadingWhitespace: '',
      text: 'item',
      delimeter: '-',
      middleWhitespace: ' ',
      taskBox: '[ ]',
    })
  })

  test('should match a numbered list item', () => {
    const line = '1. [x] item'
    const result = parseListItem(line)
    expect(result).toEqual({
      leadingWhitespace: '',
      text: 'item',
      delimeter: 1,
      middleWhitespace: ' ',
      taskBox: '[x]',
    })
  })

  test('should match a list item with leading whitespaces', () => {
    const line = '    - [ ] item'
    const result = parseListItem(line)
    expect(result).toEqual({
      leadingWhitespace: '    ',
      text: 'item',
      delimeter: '-',
      middleWhitespace: ' ',
      taskBox: '[ ]',
    })
  })

  test('should match a list item inside a blockquote', () => {
    const line = '>- [ ] item'
    const result = parseListItem(line)
    expect(result).toEqual({
      leadingWhitespace: '>',
      text: 'item',
      delimeter: '-',
      middleWhitespace: ' ',
      taskBox: '[ ]',
    })
  })

  test('should match a nested list item', () => {
    const line = '- *   - [ ] item'
    const result = parseListItem(line)
    expect(result).toEqual({
      leadingWhitespace: '- *   ',
      text: 'item',
      delimeter: '-',
      middleWhitespace: ' ',
      taskBox: '[ ]',
    })
  })

  test('should match a nested list item inside a blockquote', () => {
    const line = '> - *   - [ ] item'
    const result = parseListItem(line)
    expect(result).toEqual({
      leadingWhitespace: '> - *   ',
      text: 'item',
      delimeter: '-',
      middleWhitespace: ' ',
      taskBox: '[ ]',
    })
  })

  test('should match a multi nested list item inside multiple blockquotes', () => {
    const line = '>> >  > - * *  *   -  - [ ] item'
    const result = parseListItem(line)
    expect(result).toEqual({
      leadingWhitespace: '>> >  > - * *  *   -  ',
      text: 'item',
      delimeter: '-',
      middleWhitespace: ' ',
      taskBox: '[ ]',
    })
  })
})

describe('listItemToString', () => {
  test('correctly converts unnumbered list item', () => {
    const listItem = {
      leadingWhitespace: '',
      text: 'item',
      delimeter: '-',
      middleWhitespace: ' ',
      taskBox: '[ ]',
    }
    const result = listItemToString(listItem as ListItem)
    expect(result).toEqual('- [ ] item')
  })

  test('correctly converts numbered list item', () => {
    const listItem = {
      leadingWhitespace: '',
      text: 'item',
      delimeter: 1,
      middleWhitespace: ' ',
      taskBox: '[x]',
    }
    const result = listItemToString(listItem as ListItem)
    expect(result).toEqual('1. [x] item')
  })
})
