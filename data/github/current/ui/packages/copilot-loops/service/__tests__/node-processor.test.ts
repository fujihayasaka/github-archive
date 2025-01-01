import type {NodeValue} from '../../types/app'
import {replaceIdsInString} from '../node-processor'

describe('replaceIdsInString', () => {
  it('replaces variables with their values', () => {
    const nodeMap = {
      node1: 'value1',
      node2: 'value2',
    }

    const input = 'Text with {{node1}} and {{node2}}'
    const result = replaceIdsInString(input, nodeMap)

    expect(result).toBe('Text with value1 and value2')
  })

  it('does not replace variables that are not in the nodeMap', () => {
    const nodeMap = {
      node1: 'value1',
    }

    const input = 'Text with {{node1}} and {{nonExistentNode}}'
    const result = replaceIdsInString(input, nodeMap)

    expect(result).toBe('Text with value1 and {{nonExistentNode}}')
  })

  it('handles multiple instances of the same variable', () => {
    const nodeMap = {
      node1: 'repeated value',
    }

    const input = 'Text with {{node1}} and again {{node1}}'
    const result = replaceIdsInString(input, nodeMap)

    expect(result).toBe('Text with repeated value and again repeated value')
  })

  it('stringifies non-string values', () => {
    const nodeMap: Record<string, NodeValue> = {
      numberNode: 42,
      boolNode: true,
      arrayNode: ['1', '2', '3'],
    }

    const input = '{{numberNode}} {{boolNode}} {{arrayNode}}'
    const result = replaceIdsInString(input, nodeMap)

    expect(result).toBe('42 true ["1","2","3"]')
  })

  it('handles different behavior in code context', () => {
    const nodeMap: Record<string, NodeValue> = {
      stringNode: 'text value',
    }

    // Normal context (isInCode = false, default)
    const normalResult = replaceIdsInString('{{stringNode}}', nodeMap)
    expect(normalResult).toBe('text value')

    // Code context (isInCode = true)
    const codeResult = replaceIdsInString('{{stringNode}}', nodeMap, true)
    expect(codeResult).toBe('"text value"')
  })

  it('accesses specific fields on an object using dot notation', () => {
    const nodeMap: Record<string, NodeValue> = {
      objectNode: {
        value: {
          nested: {
            field: 'accessed value',
          },
          otherField: 42,
        },
        topLevel: 'top level value',
      },
    }

    const input = '{{objectNode.value.nested.field}} and {{objectNode.topLevel}}'
    const result = replaceIdsInString(input, nodeMap)

    expect(result).toBe('accessed value and top level value')
  })

  it('returns null when trying to use dot notation with non-objects', () => {
    const nodeMap: Record<string, NodeValue> = {
      stringNode: 'simple string',
      numberNode: 42,
    }

    const input = '{{stringNode.nonExistent}}'

    expect(() => replaceIdsInString(input, nodeMap)).toThrow(
      'Cannot access path "nonExistent" on non-object node with ID "stringNode"',
    )
  })

  it('throws error when trying to access non-existent paths in objects', () => {
    const nodeMap: Record<string, NodeValue> = {
      objectNode: {
        value: {
          nested: {
            field: 'exists',
          },
        },
      },
    }

    expect(() => {
      replaceIdsInString('{{objectNode.value.wrong.path}}', nodeMap)
    }).toThrow('Path "value.wrong.path" on node with ID "objectNode" does not have a value')
  })

  it('throws error when trying to access paths on null or undefined values', () => {
    const nodeMap: Record<string, NodeValue> = {
      objectNode: {
        nullValue: null,
        withUndefined: {
          undefinedField: undefined,
        },
      },
    }

    expect(() => {
      replaceIdsInString('{{objectNode.nullValue.something}}', nodeMap)
    }).toThrow('Path "nullValue.something" on node with ID "objectNode" does not have a value')

    expect(() => {
      replaceIdsInString('{{objectNode.withUndefined.undefinedField.deeper}}', nodeMap)
    }).toThrow('Path "withUndefined.undefinedField.deeper" on node with ID "objectNode" does not have a value')
  })

  it('combines multiple variable replacement scenarios in a single string', () => {
    // Setup a complex nodeMap with various data types and structures
    const nodeMap: Record<string, NodeValue> = {
      text: 'simple text',
      number: 42,
      bool: true,
      array: ['one', 'two', 'three'],
      object: {
        name: 'test object',
        nested: {
          value: 'nested value',
          number: 123,
          deep: {
            secret: 'found me!',
          },
        },
      },
      nullValue: null,
      withSpecialChars: 'text with "quotes" and \\ backslashes',
      emptyString: '',
      emptyArray: [],
      emptyObject: {},
    }

    // Create a complex input string with multiple replacement patterns
    const input = `
      Basic replacements: {{text}}, {{number}}, {{bool}}
      Array content: {{array}}
      Nested object access: {{object.name}}, {{object.nested.value}}, {{object.nested.deep.secret}}
      Edge cases: {{nonExistent}}, {{emptyString}}, {{emptyArray}}, {{emptyObject}}
      Here's the full object: {{object}}
      Code context example (not applied): {{text}} {{withSpecialChars}}
    `.trim()

    const result = replaceIdsInString(input, nodeMap)

    // Expected output combines all the different replacements
    const expected = `
      Basic replacements: simple text, 42, true
      Array content: ["one","two","three"]
      Nested object access: test object, nested value, found me!
      Edge cases: {{nonExistent}}, , [], {}
      Here's the full object: {"name":"test object","nested":{"value":"nested value","number":123,"deep":{"secret":"found me!"}}}
      Code context example (not applied): simple text text with "quotes" and \\ backslashes
    `.trim()

    expect(result).toBe(expected)

    // Test the same with code context for specific replacements
    const codeContextInput = 'Text: {{text}}, Special: {{withSpecialChars}}'
    const codeContextResult = replaceIdsInString(codeContextInput, nodeMap, true)

    expect(codeContextResult).toBe('Text: "simple text", Special: "text with \\"quotes\\" and \\\\ backslashes"')
  })

  it('handles array index path referencing', () => {
    const nodeMap: Record<string, NodeValue> = {
      arrayNode: {
        items: [
          {name: 'first item', properties: {color: 'red', size: 'large'}},
          {name: 'second item', properties: {color: 'blue', size: 'medium'}},
          {name: 'third item', properties: {color: 'green', size: 'small'}},
        ],
        nestedArrays: [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ],
      },
    }

    // Test accessing array elements using numeric indices
    const input = `
      First item: {{arrayNode.items.0.name}}
      Second item properties: {{arrayNode.items.1.properties.color}} and {{arrayNode.items.1.properties.size}}
      Third item: {{arrayNode.items.2}}
      Nested array values: {{arrayNode.nestedArrays.0.1}} and {{arrayNode.nestedArrays.2.0}}
    `.trim()

    const result = replaceIdsInString(input, nodeMap)

    const expected = `
      First item: first item
      Second item properties: blue and medium
      Third item: {"name":"third item","properties":{"color":"green","size":"small"}}
      Nested array values: 2 and 7
    `.trim()

    expect(result).toBe(expected)
  })

  it('returns the original string when no variables are present', () => {
    const nodeMap = {
      node1: 'value1',
    }

    const input = 'Text with no variables'
    const result = replaceIdsInString(input, nodeMap)

    expect(result).toBe('Text with no variables')
  })

  it('handles empty nodeMap', () => {
    const input = 'Text with {{node1}}'
    const result = replaceIdsInString(input, {})

    expect(result).toBe('Text with {{node1}}')
  })

  it('does not recursively replace variables in node values', () => {
    const nodeMap = {
      node1: '{{fakenode}}',
      node2: 'Text with {{another}}',
      fakenode: 'should not be replaced',
    }

    const input = 'Start {{node1}} middle {{node2}} end'
    const result = replaceIdsInString(input, nodeMap)

    // The function should replace {{node1}} with "{{fakenode}}" and {{node2}} with "Text with {{another}}"
    // But it should NOT then try to replace {{fakenode}} or {{another}} in those replaced values
    expect(result).toBe('Start {{fakenode}} middle Text with {{another}} end')
  })
})
