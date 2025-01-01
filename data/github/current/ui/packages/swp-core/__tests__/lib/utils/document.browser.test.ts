import {BLOCKS, type Block} from '@contentful/rich-text-types'

import {describe, expect, it} from '@github-ui/tests'

import {countNodesOfType} from '../../../lib/utils/document'

const mockContent: Block = {
  nodeType: BLOCKS.DOCUMENT,
  data: {},
  content: [
    {
      nodeType: BLOCKS.HEADING_2,
      data: {},
      content: [
        {
          nodeType: 'text',
          value: 'Section 1',
          marks: [],
          data: {},
        },
      ],
    },
    {
      nodeType: BLOCKS.HEADING_3,
      data: {},
      content: [
        {
          nodeType: 'text',
          value: 'Section 2',
          marks: [],
          data: {},
        },
      ],
    },
    {
      nodeType: BLOCKS.HEADING_2,
      data: {},
      content: [
        {
          nodeType: 'text',
          value: 'Section 3',
          marks: [],
          data: {},
        },
      ],
    },
  ],
}

describe('countNodesOfType', () => {
  it('counts all nodes of a given nodeType', () => {
    const count = countNodesOfType(mockContent, BLOCKS.HEADING_2)
    expect(count).toBe(2)
  })

  it('returns 0 when no nodes of the specified type are found', () => {
    const count = countNodesOfType(mockContent, BLOCKS.HEADING_4)
    expect(count).toBe(0)
  })

  it('handles nested nodes and skips text nodes', () => {
    const nestedContent: Block = {
      nodeType: BLOCKS.DOCUMENT,
      data: {},
      content: [
        {
          nodeType: BLOCKS.HEADING_2,
          data: {},
          content: [
            {
              nodeType: BLOCKS.HEADING_2,
              data: {},
              content: [
                {
                  nodeType: 'text',
                  value: 'Nested Heading',
                  marks: [],
                  data: {},
                },
              ],
            },
          ],
        },
      ],
    }

    const count = countNodesOfType(nestedContent, BLOCKS.HEADING_2)
    expect(count).toBe(2)
  })

  it('returns 1 if the root node itself matches the specified type', () => {
    const singleNode: Block = {
      nodeType: BLOCKS.HEADING_2,
      data: {},
      content: [],
    }

    const count = countNodesOfType(singleNode, BLOCKS.HEADING_2)
    expect(count).toBe(1)
  })
})
