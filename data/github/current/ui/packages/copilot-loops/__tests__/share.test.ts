import {createShareableLoop, createShareUrl, decodeSharedLoop, createLoopFromShared} from '../utils/share'
import type {Pipeline} from '../types/app'
import {compressToEncodedURIComponent} from 'lz-string'

// Mock window.location for URL creation tests
Object.defineProperty(window, 'location', {
  value: {
    origin: 'https://github.com',
  },
  writable: true,
})

describe('share utilities', () => {
  const mockPipeline: Pipeline = {
    id: 'test-id',
    title: 'Test Loop',
    description: 'A test loop for sharing',
    nodes: [
      {
        id: 'node-1',
        type: 'text',
        title: 'Input Node',
        description: 'A test input node',
        content: 'Test input content',
        inputType: {type: 'text'},
      },
      {
        id: 'node-2',
        type: 'prompt',
        title: 'Output Node',
        description: 'A test output node',
        content: 'Test output content: {{node-1}}',
      },
    ],
    updatedAt: '2023-01-01T00:00:00.000Z',
  }

  const expectedShareableData = {
    title: 'Test Loop',
    description: 'A test loop for sharing',
    nodes: mockPipeline.nodes,
  }

  describe('createShareableLoop', () => {
    it('should extract only shareable fields from a pipeline', () => {
      const result = createShareableLoop(mockPipeline)
      expect(result).toEqual(expectedShareableData)
      expect(result).not.toHaveProperty('id')
      expect(result).not.toHaveProperty('updatedAt')
    })
  })

  describe('createShareUrl', () => {
    it('should create a compressed share URL', () => {
      const result = createShareUrl(mockPipeline)
      expect(result).toMatch(/^https:\/\/github\.com\/copilot\/loop\/share\?data=/)

      // Extract the data parameter and verify it's compressed
      const url = new URL(result, window.location.origin)
      const dataParam = url.searchParams.get('data')
      expect(dataParam).toBeTruthy()

      // Should be different from base64 encoding (compressed should be shorter for this data)
      const jsonString = JSON.stringify(expectedShareableData)
      const base64Encoded = btoa(encodeURIComponent(jsonString))
      expect(dataParam).not.toBe(base64Encoded)
    })
  })

  describe('decodeSharedLoop', () => {
    let compressedData: string
    let legacyBase64Data: string

    beforeEach(() => {
      const jsonString = JSON.stringify(expectedShareableData)

      // Create compressed data (new format)
      compressedData = compressToEncodedURIComponent(jsonString)

      // Create base64 data (legacy format)
      legacyBase64Data = btoa(encodeURIComponent(jsonString))
    })

    describe('with compressed data (new format)', () => {
      it('should decode compressed loop data successfully', () => {
        const result = decodeSharedLoop(compressedData)
        expect(result).toEqual(expectedShareableData)
      })

      it('should return null for invalid compressed data', () => {
        const result = decodeSharedLoop('invalid-compressed-data')
        expect(result).toBeNull()
      })

      it('should return null for compressed data without required fields', () => {
        const incompleteData = {description: 'Missing title and nodes'}
        const incompleteCompressed = compressToEncodedURIComponent(JSON.stringify(incompleteData))
        const result = decodeSharedLoop(incompleteCompressed)
        expect(result).toBeNull()
      })
    })

    describe('with legacy base64 data (backwards compatibility)', () => {
      it('should decode legacy base64 loop data successfully', () => {
        const result = decodeSharedLoop(legacyBase64Data)
        expect(result).toEqual(expectedShareableData)
      })

      it('should return null for invalid base64 data', () => {
        const result = decodeSharedLoop('invalid-base64-data!')
        expect(result).toBeNull()
      })

      it('should return null for base64 data without required fields', () => {
        const incompleteData = {description: 'Missing title and nodes'}
        const incompleteBase64 = btoa(encodeURIComponent(JSON.stringify(incompleteData)))
        const result = decodeSharedLoop(incompleteBase64)
        expect(result).toBeNull()
      })
    })

    describe('format detection and fallback', () => {
      it('should try compressed format first, then fall back to base64', () => {
        // This tests the fallback mechanism by providing base64 data
        // that would fail compression parsing but succeed base64 parsing
        const result = decodeSharedLoop(legacyBase64Data)
        expect(result).toEqual(expectedShareableData)
      })

      it('should handle data that is neither valid compressed nor base64', () => {
        const result = decodeSharedLoop('completely-invalid-data-123')
        expect(result).toBeNull()
      })

      it('should handle empty string', () => {
        const result = decodeSharedLoop('')
        expect(result).toBeNull()
      })
    })

    describe('data validation', () => {
      it('should require title field', () => {
        const dataWithoutTitle = {
          description: 'Has description',
          nodes: mockPipeline.nodes,
        }
        const compressed = compressToEncodedURIComponent(JSON.stringify(dataWithoutTitle))
        const result = decodeSharedLoop(compressed)
        expect(result).toBeNull()
      })

      it('should require nodes field', () => {
        const dataWithoutNodes = {
          title: 'Has title',
          description: 'Has description',
        }
        const compressed = compressToEncodedURIComponent(JSON.stringify(dataWithoutNodes))
        const result = decodeSharedLoop(compressed)
        expect(result).toBeNull()
      })

      it('should allow empty description', () => {
        const dataWithEmptyDescription = {
          title: 'Has title',
          description: '',
          nodes: mockPipeline.nodes,
        }
        const compressed = compressToEncodedURIComponent(JSON.stringify(dataWithEmptyDescription))
        const result = decodeSharedLoop(compressed)
        expect(result).toEqual(dataWithEmptyDescription)
      })
    })
  })

  describe('createLoopFromShared', () => {
    it('should create a complete pipeline from shared data', () => {
      const result = createLoopFromShared(expectedShareableData)

      expect(result).toHaveProperty('id')
      expect(result.id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/) // UUID format
      expect(result.title).toBe(expectedShareableData.title)
      expect(result.description).toBe(expectedShareableData.description)
      expect(result.nodes).toEqual(expectedShareableData.nodes)
      expect(result).toHaveProperty('updatedAt')
      expect(new Date(result.updatedAt)).toBeInstanceOf(Date)
    })

    it('should handle missing description', () => {
      const dataWithoutDescription = {
        title: 'Test Title',
        nodes: mockPipeline.nodes,
      }
      const result = createLoopFromShared(dataWithoutDescription)

      expect(result.title).toBe('Test Title')
      expect(result.description).toBe('')
      expect(result.nodes).toEqual(mockPipeline.nodes)
    })

    it('should handle missing title with fallback', () => {
      const dataWithoutTitle = {
        description: 'Test Description',
        nodes: mockPipeline.nodes,
      }
      const result = createLoopFromShared(dataWithoutTitle)

      expect(result.title).toBe('Shared Loop')
      expect(result.description).toBe('Test Description')
    })

    it('should handle missing nodes with empty array', () => {
      const dataWithoutNodes = {
        title: 'Test Title',
        description: 'Test Description',
      }
      const result = createLoopFromShared(dataWithoutNodes)

      expect(result.nodes).toEqual([])
    })
  })

  describe('integration test: full encode/decode cycle', () => {
    it('should successfully encode and decode using new compression format', () => {
      // Create share URL (uses compression)
      const shareUrl = createShareUrl(mockPipeline)

      // Extract data parameter
      const url = new URL(shareUrl, window.location.origin)
      const encodedData = url.searchParams.get('data')!

      // Decode the data
      const decodedData = decodeSharedLoop(encodedData)
      expect(decodedData).toEqual(expectedShareableData)

      // Create loop from decoded data
      const newLoop = createLoopFromShared(decodedData!)
      expect(newLoop.title).toBe(mockPipeline.title)
      expect(newLoop.description).toBe(mockPipeline.description)
      expect(newLoop.nodes).toEqual(mockPipeline.nodes)
    })

    it('should successfully decode legacy base64 format in real URLs', () => {
      // Create legacy format data manually
      const jsonString = JSON.stringify(expectedShareableData)
      const legacyEncoded = btoa(encodeURIComponent(jsonString))
      const legacyUrl = `https://github.com/copilot/loop/share?data=${legacyEncoded}`

      // Extract and decode
      const url = new URL(legacyUrl, window.location.origin)
      const encodedData = url.searchParams.get('data')!
      const decodedData = decodeSharedLoop(encodedData)

      expect(decodedData).toEqual(expectedShareableData)
    })
  })
})
