import type {Pipeline} from '../../types/app'
import {validatePipeline, validatePipelineObject} from '../validate-pipeline'

const haikuGenerator: Pipeline = {
  updatedAt: '2025-01-01T00:00:00Z',
  id: 'haiku',
  title: 'Haiku Writer',
  nodes: [
    {
      id: '1',
      title: 'Topic',
      description: 'The topic of the haiku',
      type: 'text',
      content: 'Puppies',
      inputType: {type: 'text'},
    },
    {
      id: '2',
      title: 'Prompt',
      description: 'Writes a haiku',
      type: 'prompt',
      content: 'Write a haiku about {{1}}.',
    },
  ],
}

const circularAnalysis: Pipeline = {
  updatedAt: '2025-01-01T00:00:00Z',
  id: 'cycles',
  title: 'Cycles',
  nodes: [
    {
      id: '1',
      title: 'Topic',
      description: 'topic',
      type: 'text',
      content: 'GitHub',
      inputType: {type: 'text'},
    },
    {
      id: '2',
      title: 'Prompt',
      description: 'Writes an essay',
      type: 'prompt',
      content: 'Write an essay about {{1}}. Make it very different from {{4}}.',
    },
    {
      id: '3',
      title: 'Topic guess',
      description: 'guesses the essay topic',
      type: 'prompt',
      content: 'Summarize in a few words the topic of this essay: {{2}}',
    },
    {
      id: '4',
      title: 'Second essay',
      description: 'Writes an essay about the topic guess',
      type: 'prompt',
      content: 'Write an essay about {{3}}.',
    },
  ],
}

const invalidReference: Pipeline = {
  ...haikuGenerator,
  nodes: haikuGenerator.nodes.map(n =>
    n.id === '2'
      ? {
          id: '2',
          title: 'Prompt',
          description: 'Writes a haiku',
          type: 'prompt',
          content: 'Write a haiku about {{1}} and also {{42}}.',
        }
      : n,
  ),
}

const disconnected: Pipeline = {
  ...haikuGenerator,
  nodes: haikuGenerator.nodes.map(n =>
    n.id === '2'
      ? {
          id: '2',
          title: 'Prompt',
          description: 'Writes a haiku',
          type: 'prompt',
          content: 'Write a haiku about anything.',
        }
      : n,
  ),
}

const disconnectedFirstNode: Pipeline = {
  updatedAt: '2025-01-01T00:00:00Z',
  id: 'haiku',
  title: 'Haiku Writer',
  nodes: [
    {
      id: '1',
      title: 'Topic',
      description: 'The topic of the haiku',
      type: 'text',
      content: 'Puppies',
      inputType: {type: 'text'},
    },
    {
      id: '2',
      title: 'Prompt',
      description: 'Writes a haiku',
      type: 'prompt',
      content: 'Write a haiku about.',
    },
    {
      id: '3',
      title: 'Prompt part 2',
      description: 'Writes a haiku again',
      type: 'prompt',
      content: 'Improve the haikus written in {{2}}.',
    },
  ],
}

describe('validatePipelineObject', () => {
  test('valid pipeline object returns true', () => {
    expect(validatePipelineObject(haikuGenerator)).toBe(true)
  })

  test('null or non-object returns false', () => {
    expect(validatePipelineObject(null)).toBe(false)
    expect(validatePipelineObject(undefined)).toBe(false)
    expect(validatePipelineObject('string')).toBe(false)
    expect(validatePipelineObject(42)).toBe(false)
    expect(validatePipelineObject(true)).toBe(false)
  })

  test('missing title returns false', () => {
    const noTitle = {...haikuGenerator, title: undefined} as unknown as Pipeline
    expect(validatePipelineObject(noTitle)).toBe(false)
  })

  test('non-string title returns false', () => {
    const numericTitle = {...haikuGenerator, title: 42} as unknown as Pipeline
    expect(validatePipelineObject(numericTitle)).toBe(false)
  })

  test('missing nodes returns false', () => {
    const noNodes = {...haikuGenerator, nodes: undefined} as unknown as Pipeline
    expect(validatePipelineObject(noNodes)).toBe(false)
  })

  test('non-array nodes returns false', () => {
    const objectNodes = {...haikuGenerator, nodes: {}} as unknown as Pipeline
    expect(validatePipelineObject(objectNodes)).toBe(false)
  })

  test('node with invalid type returns false', () => {
    const invalidNodeType = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          type: 'invalid-type',
        },
      ],
    }
    expect(validatePipelineObject(invalidNodeType)).toBe(false)
  })

  test('node without id returns false', () => {
    const nodeWithoutId = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          id: undefined,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithoutId)).toBe(false)
  })

  test('node with non-string id returns false', () => {
    const nodeWithNumericId = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          id: 42,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithNumericId)).toBe(false)
  })

  test('node without title returns false', () => {
    const nodeWithoutTitle = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          title: undefined,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithoutTitle)).toBe(false)
  })

  test('node with non-string title returns false', () => {
    const nodeWithNumericTitle = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          title: 42,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithNumericTitle)).toBe(false)
  })

  test('node without content returns false', () => {
    const nodeWithoutContent = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          content: undefined,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithoutContent)).toBe(false)
  })

  test('node with non-string content returns false', () => {
    const nodeWithNumericContent = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          content: 42,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithNumericContent)).toBe(false)
  })

  test('text node without inputType returns false', () => {
    const nodeWithoutInputType = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: undefined,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithoutInputType)).toBe(false)
  })

  test('text node with invalid inputType returns false', () => {
    const nodeWithInvalidInputType = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'invalid-type'},
        },
      ],
    }
    expect(validatePipelineObject(nodeWithInvalidInputType)).toBe(false)
  })

  test('range input without min or max returns false', () => {
    const rangeWithoutMinMax = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'range'},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithoutMinMax)).toBe(false)
  })

  test('range input with min but without max returns false', () => {
    const rangeWithOnlyMin = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'range', min: 1},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithOnlyMin)).toBe(false)
  })

  test('range input with max but without min returns false', () => {
    const rangeWithOnlyMax = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'range', max: 10},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithOnlyMax)).toBe(false)
  })

  test('range input with non-numeric min returns false', () => {
    const rangeWithNonNumericMin = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'range', min: '1', max: 10},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithNonNumericMin)).toBe(false)
  })

  test('range input with non-numeric max returns false', () => {
    const rangeWithNonNumericMax = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'range', min: 1, max: '10'},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithNonNumericMax)).toBe(false)
  })

  test('range input with valid min and max returns true', () => {
    const validRange = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'range', min: 1, max: 10},
        },
      ],
    }
    expect(validatePipelineObject(validRange)).toBe(true)
  })

  test('select input without options returns false', () => {
    const selectWithoutOptions = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'select'},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(selectWithoutOptions)).toBe(false)
  })

  test('select input with empty options returns false', () => {
    const selectWithEmptyOptions = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'select', options: []},
        },
      ],
    }
    expect(validatePipelineObject(selectWithEmptyOptions)).toBe(false)
  })

  test('select input with non-array options returns false', () => {
    const selectWithNonArrayOptions = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'select', options: 'options'},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(selectWithNonArrayOptions)).toBe(false)
  })

  test('select input with valid options returns true', () => {
    const validSelect = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'select', options: ['option1', 'option2']},
        },
      ],
    }
    expect(validatePipelineObject(validSelect)).toBe(true)
  })

  test('file input without fileType returns false', () => {
    const fileWithoutType = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'file'},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(fileWithoutType)).toBe(false)
  })

  test('file input with non-string fileType returns false', () => {
    const fileWithNumericType = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'file', fileType: 42},
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(fileWithNumericType)).toBe(false)
  })

  test('file input with valid fileType returns true', () => {
    const validFile = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'file', fileType: 'text/plain'},
        },
      ],
    }
    expect(validatePipelineObject(validFile)).toBe(true)
  })

  test('text node with valid text inputType returns true', () => {
    const validTextInput = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'text'},
        },
      ],
    }
    expect(validatePipelineObject(validTextInput)).toBe(true)
  })
})

describe('validate-pipeline', () => {
  test('valid pipeline', () => {
    const errors = validatePipeline(haikuGenerator)
    expect(errors).toHaveLength(0)
  })

  test('pipeline with cycle', () => {
    const errors = validatePipeline(circularAnalysis)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('cycle')
    expect(errors[0]?.involvedNodes).toHaveLength(3)
    expect(errors[0]?.involvedNodes).toContain('2')
    expect(errors[0]?.involvedNodes).toContain('3')
    expect(errors[0]?.involvedNodes).toContain('4')
  })

  test('reference to nonexistent node', () => {
    const errors = validatePipeline(invalidReference)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('nonexistent node')
  })

  test('disconnected pipeline', () => {
    const errors = validatePipeline(disconnected)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('unreachable nodes: 2')
  })

  test('disconnected first node', () => {
    const errors = validatePipeline(disconnectedFirstNode)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('unreachable nodes: 1')
  })

  test('pipeline title required', () => {
    const noTitle = {...haikuGenerator, title: undefined} as unknown as Pipeline
    const errors = validatePipeline(noTitle)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('title')
  })

  test('pipeline nodes required', () => {
    const noNodes = {...haikuGenerator, nodes: []}
    const errors = validatePipeline(noNodes)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('nodes')
  })

  test('node title required', () => {
    const nodeWithoutTitle = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          title: undefined,
        },
      ],
    } as unknown as Pipeline
    const errors = validatePipeline(nodeWithoutTitle)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('title')
  })

  test('range input', () => {
    const nodeWithoutID = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'range', min: 5, max: undefined},
        },
      ],
    } as unknown as Pipeline
    const errors = validatePipeline(nodeWithoutID)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('range')
    expect(errors[0]?.error).toContain('max')
  })

  test('boolean input', () => {
    const nodeWithoutID = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'boolean', content: 'neither true nor false'},
        },
      ],
    } as unknown as Pipeline
    const errors = validatePipeline(nodeWithoutID)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('true')
    expect(errors[0]?.error).toContain('false')
  })

  test('select input', () => {
    const nodeWithoutID = {
      ...haikuGenerator,
      nodes: [
        {
          ...haikuGenerator.nodes[0],
          inputType: {type: 'select', content: 'D', options: ['A', 'B', 'C']},
        },
      ],
    } as unknown as Pipeline
    const errors = validatePipeline(nodeWithoutID)
    expect(errors).toHaveLength(1)
    expect(errors[0]?.error).toContain('select')
    expect(errors[0]?.error).toContain('options')
  })
})

describe('validatePipelineObject - extended validations', () => {
  const validTextPipeline: Pipeline = {
    id: 'test-text',
    title: 'Text Input Test',
    nodes: [
      {
        id: '1',
        title: 'Input Node',
        description: 'Test input',
        type: 'text',
        content: 'Test content',
        inputType: {type: 'text'},
      },
    ],
    updatedAt: '2025-01-01T00:00:00Z',
  }

  const validRangePipeline: Pipeline = {
    id: 'test-range',
    title: 'Range Input Test',
    nodes: [
      {
        id: '1',
        title: 'Range Input',
        description: 'Test range input',
        type: 'text',
        content: '5',
        inputType: {type: 'range', min: 1, max: 10},
      },
    ],
    updatedAt: '2025-01-01T00:00:00Z',
  }

  const validSelectPipeline: Pipeline = {
    id: 'test-select',
    title: 'Select Input Test',
    nodes: [
      {
        id: '1',
        title: 'Select Input',
        description: 'Test select input',
        type: 'text',
        content: 'Option A',
        inputType: {type: 'select', options: ['Option A', 'Option B', 'Option C']},
      },
    ],
    updatedAt: '2025-01-01T00:00:00Z',
  }

  test('node without content returns false', () => {
    const nodeWithoutContent = {
      ...validTextPipeline,
      nodes: [
        {
          ...validTextPipeline.nodes[0],
          content: undefined,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithoutContent)).toBe(false)
  })

  test('node with non-string content returns false', () => {
    const nodeWithNumericContent = {
      ...validTextPipeline,
      nodes: [
        {
          ...validTextPipeline.nodes[0],
          content: 42,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithNumericContent)).toBe(false)
  })

  test('text node with valid inputType returns true', () => {
    expect(validatePipelineObject(validTextPipeline)).toBe(true)
  })

  test('range input with valid min and max returns true', () => {
    expect(validatePipelineObject(validRangePipeline)).toBe(true)
  })

  test('range input with min but without max returns false', () => {
    const rangeWithoutMax = {
      ...validRangePipeline,
      nodes: [
        {
          ...validRangePipeline.nodes[0],
          inputType: {
            type: 'range',
            min: 1,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithoutMax)).toBe(false)
  })

  test('range input with max but without min returns false', () => {
    const rangeWithoutMin = {
      ...validRangePipeline,
      nodes: [
        {
          ...validRangePipeline.nodes[0],
          inputType: {
            type: 'range',
            max: 10,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithoutMin)).toBe(false)
  })

  test('range input with non-numeric min returns false', () => {
    const rangeWithNonNumericMin = {
      ...validRangePipeline,
      nodes: [
        {
          ...validRangePipeline.nodes[0],
          inputType: {
            type: 'range',
            min: '1' as unknown as number,
            max: 10,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithNonNumericMin)).toBe(false)
  })

  test('range input with non-numeric max returns false', () => {
    const rangeWithNonNumericMax = {
      ...validRangePipeline,
      nodes: [
        {
          ...validRangePipeline.nodes[0],
          inputType: {
            type: 'range',
            min: 1,
            max: '10' as unknown as number,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithNonNumericMax)).toBe(false)
  })

  test('select input with valid options returns true', () => {
    expect(validatePipelineObject(validSelectPipeline)).toBe(true)
  })

  test('text node with valid text inputType returns true', () => {
    expect(validatePipelineObject(validTextPipeline)).toBe(true)
  })

  test('node with an invalid type returns false', () => {
    const nodeWithInvalidType = {
      ...validTextPipeline,
      nodes: [
        {
          ...validTextPipeline.nodes[0],
          type: 'invalid-type',
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithInvalidType)).toBe(false)
  })
})

describe('validatePipelineObject - additional validations', () => {
  const validTextNodePipeline: Pipeline = {
    updatedAt: '2025-01-01T00:00:00Z',
    id: 'text-node-test',
    title: 'Text Node Test',
    nodes: [
      {
        id: '1',
        title: 'Input Node',
        description: 'Test input node',
        type: 'text',
        content: 'Test content',
        inputType: {type: 'text'},
      },
    ],
  }

  const validRangeNodePipeline: Pipeline = {
    updatedAt: '2025-01-01T00:00:00Z',
    id: 'range-node-test',
    title: 'Range Node Test',
    nodes: [
      {
        id: '1',
        title: 'Range Input',
        description: 'Test range input',
        type: 'text',
        content: '5',
        inputType: {type: 'range', min: 1, max: 10},
      },
    ],
  }

  const validSelectNodePipeline: Pipeline = {
    updatedAt: '2025-01-01T00:00:00Z',
    id: 'select-node-test',
    title: 'Select Node Test',
    nodes: [
      {
        id: '1',
        title: 'Select Input',
        description: 'Test select input',
        type: 'text',
        content: 'Option A',
        inputType: {type: 'select', options: ['Option A', 'Option B', 'Option C']},
      },
    ],
  }

  const validFileNodePipeline: Pipeline = {
    updatedAt: '2025-01-01T00:00:00Z',
    id: 'file-node-test',
    title: 'File Node Test',
    nodes: [
      {
        id: '1',
        title: 'File Input',
        description: 'Test file input',
        type: 'text',
        content: 'file.txt',
        inputType: {type: 'file', fileType: 'document'},
      },
    ],
  }

  test('node without content returns false', () => {
    const nodeWithoutContent = {
      ...validTextNodePipeline,
      nodes: [
        {
          ...validTextNodePipeline.nodes[0],
          content: undefined,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithoutContent)).toBe(false)
  })

  test('node with non-string content returns false', () => {
    const nodeWithNumericContent = {
      ...validTextNodePipeline,
      nodes: [
        {
          ...validTextNodePipeline.nodes[0],
          content: 42,
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithNumericContent)).toBe(false)
  })

  test('text node with valid inputType returns true', () => {
    expect(validatePipelineObject(validTextNodePipeline)).toBe(true)
  })

  test('range input with valid min and max returns true', () => {
    expect(validatePipelineObject(validRangeNodePipeline)).toBe(true)
  })

  test('range input with min but without max returns false', () => {
    const rangeWithoutMax = {
      ...validRangeNodePipeline,
      nodes: [
        {
          ...validRangeNodePipeline.nodes[0],
          inputType: {
            type: 'range',
            min: 1,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithoutMax)).toBe(false)
  })

  test('range input with max but without min returns false', () => {
    const rangeWithoutMin = {
      ...validRangeNodePipeline,
      nodes: [
        {
          ...validRangeNodePipeline.nodes[0],
          inputType: {
            type: 'range',
            max: 10,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithoutMin)).toBe(false)
  })

  test('range input with non-numeric min returns false', () => {
    const rangeWithNonNumericMin = {
      ...validRangeNodePipeline,
      nodes: [
        {
          ...validRangeNodePipeline.nodes[0],
          inputType: {
            type: 'range',
            min: '1' as unknown as number,
            max: 10,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithNonNumericMin)).toBe(false)
  })

  test('range input with non-numeric max returns false', () => {
    const rangeWithNonNumericMax = {
      ...validRangeNodePipeline,
      nodes: [
        {
          ...validRangeNodePipeline.nodes[0],
          inputType: {
            type: 'range',
            min: 1,
            max: '10' as unknown as number,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(rangeWithNonNumericMax)).toBe(false)
  })

  test('select input with valid options returns true', () => {
    expect(validatePipelineObject(validSelectNodePipeline)).toBe(true)
  })

  test('select input with non-array options returns false', () => {
    const selectWithNonArrayOptions = {
      ...validSelectNodePipeline,
      nodes: [
        {
          ...validSelectNodePipeline.nodes[0],
          inputType: {
            type: 'select',
            options: 'options' as unknown as string[],
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(selectWithNonArrayOptions)).toBe(false)
  })

  test('select input with empty options returns false', () => {
    const selectWithEmptyOptions = {
      ...validSelectNodePipeline,
      nodes: [
        {
          ...validSelectNodePipeline.nodes[0],
          inputType: {
            type: 'select',
            options: [],
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(selectWithEmptyOptions)).toBe(false)
  })

  test('file input with valid fileType returns true', () => {
    expect(validatePipelineObject(validFileNodePipeline)).toBe(true)
  })

  test('file input without fileType returns false', () => {
    const fileWithoutType = {
      ...validFileNodePipeline,
      nodes: [
        {
          ...validFileNodePipeline.nodes[0],
          inputType: {
            type: 'file',
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(fileWithoutType)).toBe(false)
  })

  test('file input with non-string fileType returns false', () => {
    const fileWithNumericType = {
      ...validFileNodePipeline,
      nodes: [
        {
          ...validFileNodePipeline.nodes[0],
          inputType: {
            type: 'file',
            fileType: 42 as unknown as string,
          },
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(fileWithNumericType)).toBe(false)
  })

  test('node with an invalid type returns false', () => {
    const nodeWithInvalidType = {
      ...validTextNodePipeline,
      nodes: [
        {
          ...validTextNodePipeline.nodes[0],
          type: 'invalid-type',
        },
      ],
    } as unknown as Pipeline
    expect(validatePipelineObject(nodeWithInvalidType)).toBe(false)
  })
})
