import type {DiffLineType} from '@github-ui/diffs/types'
import {mockMarkersData} from '../../test-utils/files-changed/markers-mock-data'
import {findMarkersByPosition} from '../diff-helpers'

test('findMarkersByPosition returns correct threads and annotations data for DELETION lines', () => {
  const mockDiffLine = {
    left: 3,
    right: 2,
    blobLineNumber: 3,
    html: 'deferred text',
    text: 'deferred text',
    type: 'DELETION' as DiffLineType,
  }

  const mockDiffSummary = {
    changeType: 'MODIFIED',
    isCodeowner: false,
    isManifestFile: false,
    isVendored: false,
    linesChanged: 0,
    linesAdded: 0,
    linesDeleted: 0,
    markedAsViewed: false,
    path: 'owned_files/collaborator/README.md',
    pathDigest: '9c28e52c6faa66e1c4ab19c843b678688fa1753dc33a21af539dccc973509a93',
    highestAnnotationLevel: undefined,
    totalCommentsCount: 0,
    markersMap: {L3: {threads: [{id: 15}], annotations: []}},
  }

  const result = findMarkersByPosition(mockDiffLine, mockDiffSummary, mockMarkersData)

  expect(result).toEqual({
    threadsData: {
      threads: [
        {
          id: '15',
          isOutdated: false,
          commentsData: {
            __id: undefined,
            comments: expect.any(Array),
            totalCount: 1,
          },
          diffSide: 'LEFT',
          line: 3,
          startDiffSide: undefined,
          startLine: undefined,
        },
      ],
      totalCommentsCount: 1,
      totalCount: 1,
    },
    annotationsData: {
      totalCount: 0,
      annotations: [],
    },
  })
})

test('findMarkersByPosition returns correct threads and annotations data for CONTEXT lines', () => {
  const mockDiffLine = {
    left: 3,
    right: 2,
    blobLineNumber: 3,
    html: 'deferred text',
    text: 'deferred text',
    type: 'CONTEXT' as DiffLineType,
  }

  const mockDiffSummary = {
    changeType: 'MODIFIED',
    isCodeowner: false,
    isManifestFile: false,
    isVendored: false,
    markedAsViewed: false,
    linesAdded: 0,
    linesDeleted: 0,
    linesChanged: 0,
    path: 'owned_files/collaborator/README.md',
    pathDigest: '9c28e52c6faa66e1c4ab19c843b678688fa1753dc33a21af539dccc973509a93',
    highestAnnotationLevel: undefined,
    totalCommentsCount: 0,
    markersMap: {R2: {threads: [{id: 15}], annotations: []}},
  }

  const result = findMarkersByPosition(mockDiffLine, mockDiffSummary, mockMarkersData)

  expect(result).toEqual({
    threadsData: {
      threads: [
        {
          id: '15',
          isOutdated: false,
          commentsData: {
            __id: undefined,
            comments: expect.any(Array),
            totalCount: 1,
          },
          diffSide: 'RIGHT',
          line: 2,
          startDiffSide: undefined,
          startLine: undefined,
        },
      ],
      totalCommentsCount: 1,
      totalCount: 1,
    },
    annotationsData: {
      totalCount: 0,
      annotations: [],
    },
  })
})

test('findMarkersByPosition returns correct threads and annotations data for ADDITION lines', () => {
  const mockDiffLine = {
    left: 3,
    right: 2,
    blobLineNumber: 3,
    html: 'deferred text',
    text: 'deferred text',
    type: 'ADDITION' as DiffLineType,
  }

  const mockDiffSummary = {
    changeType: 'MODIFIED',
    isCodeowner: false,
    isManifestFile: false,
    isVendored: false,
    markedAsViewed: false,
    linesAdded: 0,
    linesDeleted: 0,
    linesChanged: 0,
    path: 'owned_files/collaborator/README.md',
    pathDigest: '9c28e52c6faa66e1c4ab19c843b678688fa1753dc33a21af539dccc973509a93',
    highestAnnotationLevel: undefined,
    totalCommentsCount: 0,
    markersMap: {R2: {threads: [{id: 15}], annotations: []}},
  }

  const result = findMarkersByPosition(mockDiffLine, mockDiffSummary, mockMarkersData)

  expect(result).toEqual({
    threadsData: {
      threads: [
        {
          id: '15',
          isOutdated: false,
          commentsData: {
            __id: undefined,
            comments: expect.any(Array),
            totalCount: 1,
          },
          diffSide: 'RIGHT',
          line: 2,
          startDiffSide: undefined,
          startLine: undefined,
        },
      ],
      totalCommentsCount: 1,
      totalCount: 1,
    },
    annotationsData: {
      totalCount: 0,
      annotations: [],
    },
  })
})
