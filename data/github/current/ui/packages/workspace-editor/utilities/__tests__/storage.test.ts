import type {PersistedDiffs} from '../file-syncer-types'
import {getTotalStorageUsed, percentageStorageUsed, reachedStorageThreshold} from '../storage'

describe('getTotalStorageUsed', () => {
  const encoder = new TextEncoder()

  beforeEach(() => {
    localStorage.clear()
  })

  test('returns 0 when localStorage is empty', () => {
    expect(getTotalStorageUsed()).toBe(0)
  })

  test('returns correct size for a patches object', () => {
    const patches: PersistedDiffs = {
      sessionId: 'abc',
      latestTimestamp: 1734025030904,
      diffs: [
        {
          path: 'src/file_to.exclude',
          currentFileStatus: 'M',
          originalFileStatus: 'M',
          diff: {
            oldFileName: 'src/file_to.exclude',
            newFileName: 'src/file_to.exclude',
            hunks: [
              {
                oldStart: 1,
                oldLines: 3,
                newStart: 1,
                newLines: 4,
                lines: [' Sample line', '- removed line', '+ added line'],
                linedelimiters: ['\n', '\n', '\n'],
              },
            ],
            isDeleted: false,
            ignoreReason: null,
          },
        },
      ],
    }

    localStorage.setItem('patches', JSON.stringify(patches))
    const expectedSize = encoder.encode('patches').length + encoder.encode(JSON.stringify(patches)).length
    expect(getTotalStorageUsed()).toBe(expectedSize)
  })
})

describe('percentageStorageUsed', () => {
  test('calculates correct percentage when storage used is half of max size', () => {
    const halfMaxSize = 2.5 * 1024 * 1024
    expect(percentageStorageUsed(halfMaxSize)).toBe(50)
  })
})

describe('reachedStorageThreshold', () => {
  test('returns false when storage used is below the threshold', () => {
    const storageUsed = (5 * 1024 * 1024 * 85) / 100
    expect(reachedStorageThreshold(storageUsed)).toBe(false)
  })

  test('returns true when storage used is above the threshold', () => {
    const storageUsed = (5 * 1024 * 1024 * 95) / 100
    expect(reachedStorageThreshold(storageUsed)).toBe(true)
  })
})
