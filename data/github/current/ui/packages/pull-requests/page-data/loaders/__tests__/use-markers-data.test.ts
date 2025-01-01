import {buildAnnotation} from '@github-ui/conversations/test-utils'
import {generateMockComment, generateMockThread} from '../../../test-utils/files-changed/markers-mock-data'
import {countComments, filterMarkersData, type Markers} from '../use-markers-data'

describe('filterMarkersData', () => {
  const mockThread1 = generateMockThread({id: '1'})
  const mockThread2 = generateMockThread({id: '2'})
  const mockAnnotation1 = buildAnnotation({id: 'relayId1', databaseId: 3, path: 'file.txt'})
  const mockAnnotation2 = buildAnnotation({id: 'relayId2', databaseId: 4, path: 'file2.txt'})

  const mockMarkers: Markers = {
    threads: {
      1: mockThread1,
      2: mockThread2,
    },
    annotations: {
      3: mockAnnotation1,
      4: mockAnnotation2,
    },
  }

  it('returns undefined when data is undefined', () => {
    expect(filterMarkersData(undefined, [1], [1])).toBeUndefined()
  })

  it('filters threads and annotations by their IDs', () => {
    const result = filterMarkersData(mockMarkers, [1], [4])

    expect(result).toEqual({
      threads: {1: mockThread1},
      annotations: {4: mockAnnotation2},
    })
  })

  it('returns undefined when filtered threads and annotations are both empty', () => {
    expect(filterMarkersData(mockMarkers, [3], [1])).toBeUndefined()
  })

  it('returns results when at least one filter produces results', () => {
    const threadsOnlyResult = filterMarkersData(mockMarkers, [1], [1])
    expect(threadsOnlyResult).toEqual({
      threads: {1: mockThread1},
      annotations: {},
    })

    const annotationsOnlyResult = filterMarkersData(mockMarkers, [3], [3])
    expect(annotationsOnlyResult).toEqual({
      threads: {},
      annotations: {3: mockAnnotation1},
    })
  })

  it('returns all requested IDs when they exist', () => {
    const result = filterMarkersData(mockMarkers, [1, 2], [3, 4])
    expect(result).toEqual(mockMarkers)
  })
})

describe('countCommentsInThread', () => {
  const thread1 = generateMockThread({comments: [generateMockComment({}), generateMockComment({})], id: '1'})
  const thread2 = generateMockThread({
    comments: [generateMockComment({}), generateMockComment({}), generateMockComment({})],
    id: '2',
  })
  const thread3 = generateMockThread({comments: [generateMockComment({})], id: '3'})
  const resolvedThread = generateMockThread({
    comments: [generateMockComment({})],
    id: '4',
    isResolved: true,
  })
  const outdatedThread = generateMockThread({
    comments: [generateMockComment({})],
    id: '5',
    isOutdated: true,
  })

  const markersData: Markers = {
    threads: {
      1: thread1,
      2: thread2,
      3: thread3,
      4: resolvedThread,
      5: outdatedThread,
    },
    annotations: {},
  }

  it('counts comments in a thread', () => {
    const count = countComments(markersData, [1])
    expect(count).toBe(2)
  })

  it('counts comments in multiple threads', () => {
    const count = countComments(markersData, [1, 2])
    expect(count).toBe(5)
  })

  it('does not count comments in resolved threads', () => {
    const count = countComments(markersData, [4])
    expect(count).toBe(0)
  })

  it('does not count comments in outdated threads', () => {
    const count = countComments(markersData, [5])
    expect(count).toBe(0)
  })

  it('counts comments in all threads when no IDs are provided', () => {
    const count = countComments(markersData)
    expect(count).toBe(6)
  })

  it('returns 0 when no threads are provided', () => {
    const count = countComments(markersData, [])
    expect(count).toBe(0)
  })

  it('returns 0 when no data is provided', () => {
    const count = countComments(undefined, [1])
    expect(count).toBe(0)
  })
})
