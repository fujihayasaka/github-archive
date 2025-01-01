import {matchQueriesToServiceOwners} from '../generate-serviceowners'

jest.mock('fs')
jest.mock('@github-ui/find-serviceowners', () => ({
  findServiceowners: jest.fn((path: string) => {
    if (path === 'path/to/myFile.ts') {
      return ['myService']
    }

    return null
  }),
}))

describe('generateServiceOwners', () => {
  it('matchQueriesToServiceOwners, parses service owners correctly', () => {
    const matches = {
      'path/to/myFile.ts': 'someDigest',
    }
    const queries = {
      someDigest: 'query RelayMockPayloadGeneratorTest1Query { me { id } }',
    }

    const result = matchQueriesToServiceOwners(matches, queries)

    expect(result).toEqual({
      myService: {
        someDigest: 'query RelayMockPayloadGeneratorTest1Query { me { id } }',
      },
    })
  })

  it('Adds unknown service owners to the unknown service owner file', () => {
    const matches = {
      'path/to/unknownFile.ts': 'someDigest',
    }
    const queries = {
      someDigest: 'query RelayMockPayloadGeneratorTest1Query { me { id } }',
    }

    const result = matchQueriesToServiceOwners(matches, queries)

    expect(result).toEqual({
      unknown: {
        someDigest: 'query RelayMockPayloadGeneratorTest1Query { me { id } }',
      },
    })
  })
})
