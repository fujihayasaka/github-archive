import {
  getQueriesFromAllFiles,
  writeQueryDigestsToFile,
  matchQueriesToServiceOwners,
  createJsonFilesForServiceOwners,
} from '../generate-serviceowners'
import fs from 'fs'

jest.mock('fs')
jest.mock('@github-ui/find-serviceowners', () => ({
  findServiceowners: jest.fn((path: string) => {
    if (path === 'path/to/myFile.ts') {
      return ['myService']
    }

    return null
  }),
}))
const mockedReadFileSync = fs.readFileSync as jest.MockedFunction<typeof fs.readFileSync>
const mockedWriteFileSync = fs.writeFileSync as jest.MockedFunction<typeof fs.writeFileSync>

describe('generateServiceOwners', () => {
  it('getQueriesFromAllFiles: Reads all queries from all files in the given directory', () => {
    const jsonObject = {
      query: 'query RelayMockPayloadGeneratorTest1Query { me { id } }',
    }

    mockedReadFileSync.mockReturnValue(JSON.stringify(jsonObject))

    const queries = getQueriesFromAllFiles('some/path/file.json')
    expect(queries).toEqual(jsonObject)
  })

  it('getQueriesFromAllFiles: Raises in case of any error', () => {
    mockedReadFileSync.mockReturnValue("randomStuffThat'sNotJson")
    expect(() => getQueriesFromAllFiles('some/path/file.json')).toThrow()
  })

  it('writeQueryDigestsToFile writes the query digests to the given file', () => {
    const queryDigests = {
      '123123': 'someDigest',
      '1232333': 'someDigest',
    }
    const somePath = 'some/path/file.txt'
    writeQueryDigestsToFile(queryDigests, somePath)
    expect(mockedWriteFileSync).toHaveBeenCalledWith(somePath, '123123\n1232333\n')
  })

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

  it('Correctly write the queries to a file name after the service owner', () => {
    const result = {
      myService: {
        someDigest: 'query RelayMockPayloadGeneratorTest1Query { me { id } }',
      },
    }
    createJsonFilesForServiceOwners(result, 'some/path')
    expect(mockedWriteFileSync).toHaveBeenCalledWith(
      'some/path/myService.json',
      JSON.stringify(result.myService, null, 2),
    )
  })
})
