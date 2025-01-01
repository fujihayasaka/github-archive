import {parseDirective, parseDirectives} from './parse-node'
import type {StylingDirectiveNode, StylingDirective} from '../types'

describe('parseDirective', () => {
  test('should parse node when it is an array', () => {
    const node: StylingDirectiveNode = [10, 20, 'highlight']
    const result = parseDirective(node)
    expect(result).toEqual({s: 10, e: 20, c: 'highlight'})
  })

  test('should return node when it is an object', () => {
    const node: StylingDirective = {s: 5, e: 15, c: 'bold'}
    const result = parseDirective(node)
    expect(result).toEqual(node)
  })
})

describe('parseDirectives', () => {
  afterEach(() => {
    jest.restoreAllMocks()
  })

  test('should return empty array when directives is empty', () => {
    const directives: StylingDirectiveNode[] = []
    const result = parseDirectives(directives)
    expect(result).toEqual([])
  })

  test('should parse array of nodes', () => {
    const directives: StylingDirectiveNode[] = [
      [10, 20, 'pl-k'],
      [30, 40, 'pl-s'],
    ]
    const result = parseDirectives(directives)
    expect(result).toEqual([
      {s: 10, e: 20, c: 'pl-k'},
      {s: 30, e: 40, c: 'pl-s'},
    ])
  })

  test('should return array of objects as is', () => {
    const directives: StylingDirective[] = [
      {s: 5, e: 15, c: 'pl-k'},
      {s: 25, e: 35, c: 'pl-s'},
    ]
    const result = parseDirectives(directives)
    expect(result).toEqual(directives)
  })

  test('should only call parseDirective once if directive is already properly formatted', () => {
    jest.mock('./parse-node')

    const mockParseDirective = parseDirective as jest.Mock

    const directives: StylingDirective[] = [
      {s: 5, e: 15, c: 'pl-k'},
      {s: 25, e: 35, c: 'pl-s'},
      {s: 45, e: 55, c: 'pl-c'},
    ]
    const result = parseDirectives(directives)
    expect(result).toEqual(directives)
    expect(mockParseDirective).toHaveBeenCalledTimes(1)
  })

  test('should call parseDirective for each directive if not already properly formatted', () => {
    jest.mock('./parse-node')

    const mockParseDirective = parseDirective as jest.Mock

    const directives: StylingDirectiveNode[] = [
      [5, 15, 'pl-k'],
      [25, 35, 'pl-s'],
      [45, 55, 'pl-c'],
    ]
    const result = parseDirectives(directives)
    expect(result).toEqual(directives)
    expect(mockParseDirective).toHaveBeenCalledTimes(3)
  })
})
