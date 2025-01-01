/* eslint eslint-comments/no-use: off */
/* eslint-disable @github-ui/github-monorepo/filename-convention */
// This disabled the filename convention rule because the file it is testing uses kebab case because it is NOT a tsx file.
// But this file is a .tsx file because it uses a React.Fragment for testing. In order to keep the file names in sync
// we need to disable this filename convention
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {renderHook} from '@testing-library/react'
import React from 'react'

import {COPILOT_SPACES_PATH} from '../copilot-chat-helpers'
import type {CopilotChatThread} from '../copilot-chat-types'
import {
  customCopilotApiPath,
  customCopilotIdFromThread,
  customCopilotMatchesId,
  findCustomCopilot,
  getRepositoryFromOrgSearchQuery,
  isCopilotSpaceEditPath,
  isCopilotSpacePath,
  useRouteSpaceId,
} from '../custom-copilots-helpers'

// Mock ssrSafeLocation
jest.mock('@github-ui/ssr-utils', () => ({
  ssrSafeLocation: {
    pathname: '',
  },
}))

// Test wrapper component to provide React context
const wrapper = ({children}: {children: React.ReactNode}) => <React.Fragment>{children}</React.Fragment>

describe('customCopilotApiPath', () => {
  test('returns base path when id is null', () => {
    expect(customCopilotApiPath(null)).toBe(COPILOT_SPACES_PATH)
  })

  test('returns base path when id is undefined', () => {
    expect(customCopilotApiPath(undefined)).toBe(COPILOT_SPACES_PATH)
  })

  test('returns base path if passed an object that does not contain an id', () => {
    expect(customCopilotApiPath({owner: 'test-owner'})).toBe(COPILOT_SPACES_PATH)
  })

  test('returns path with owner when owner is present', () => {
    const id = {
      id: 123,
      owner: 'test-owner',
    }
    expect(customCopilotApiPath(id)).toBe(`${COPILOT_SPACES_PATH}/test-owner/123`)
  })

  test('returns custom copilots path when no owner', () => {
    const id = {
      id: 123,
    }
    expect(customCopilotApiPath(id)).toBe('/custom_copilots/123')
  })
})

describe('customCopilotMatchesId', () => {
  describe('when customCopilotId has an owner', () => {
    test('returns true when id and owner match', () => {
      const customCopilot = {
        id: 123,
        owner: 'test-owner',
        oldId: 123,
      }
      const customCopilotId = {
        id: 123,
        owner: 'test-owner',
        oldId: undefined,
      }
      expect(customCopilotMatchesId(customCopilot, customCopilotId)).toBe(true)
    })

    test('returns false when id matches but owner does not', () => {
      const customCopilot = {
        id: 123,
        owner: 'test-owner',
        oldId: 123,
      }
      const customCopilotId = {
        id: 123,
        owner: 'different-owner',
      }

      expect(customCopilotMatchesId(customCopilot, customCopilotId)).toBe(false)
    })

    test('returns false if id matches but owner does not', () => {
      const customCopilot = {
        id: 2,
        owner: 'octocat',
        oldId: 42,
      }
      const customCopilotId = {
        id: 2,
        owner: 'wrong',
      }
      expect(customCopilotMatchesId(customCopilot, customCopilotId)).toBe(false)
    })
  })

  describe('when customCopilotId owner is undefined', () => {
    test('returns true when oldId', () => {
      const customCopilot = {
        id: 123,
        owner: 'test-owner',
        oldId: 456,
      }
      const customCopilotId = {
        id: 456,
      }
      expect(customCopilotMatchesId(customCopilot, customCopilotId)).toBe(true)
    })

    test('returns false when oldId matches, id doesnt', () => {
      const customCopilot = {
        id: 123,
        owner: 'test-owner',
        oldId: 456,
      }
      const customCopilotId = {
        id: 123,
      }
      expect(customCopilotMatchesId(customCopilot, customCopilotId)).toBe(false)
    })

    test('returns true when ids match and neither has owner', () => {
      const customCopilot = {
        id: 123,
        oldId: 123,
      }
      const customCopilotId = {
        id: 123,
      }
      expect(customCopilotMatchesId(customCopilot, customCopilotId)).toBe(true)
    })

    test('returns true if oldId is a match', () => {
      const customCopilot = {
        id: 123,
        oldId: 456,
      }
      const customCopilotId = {
        id: 456,
      }
      expect(customCopilotMatchesId(customCopilot, customCopilotId)).toBe(true)
    })
  })

  describe('customCopilotIdFromThread', () => {
    test('returns null when thread is undefined', () => {
      expect(customCopilotIdFromThread(undefined)).toBeNull()
    })

    test('returns null when thread is null', () => {
      expect(customCopilotIdFromThread(null)).toBeNull()
    })

    test('returns null when thread has no customCopilotID', () => {
      const thread = {} as CopilotChatThread
      expect(customCopilotIdFromThread(thread)).toBeNull()
    })

    test('returns id without owner when thread has no customCopilotOwner', () => {
      const thread = {
        customCopilotID: 123,
      } as CopilotChatThread
      expect(customCopilotIdFromThread(thread)).toEqual({
        id: 123,
      })
    })

    test('returns id with owner when thread has both properties', () => {
      const thread = {
        customCopilotID: 123,
        customCopilotOwner: 'test-owner',
      } as CopilotChatThread
      expect(customCopilotIdFromThread(thread)).toEqual({
        id: 123,
        owner: 'test-owner',
      })
    })

    describe('isCopilotSpaceEditPath', () => {
      beforeEach(() => {
        // Reset ssrSafeLocation pathname
        ;(ssrSafeLocation as {pathname: string}).pathname = ''
      })

      test('returns true for /copilot/spaces/:owner/:number/edit style paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/testowner/123/edit'
        expect(isCopilotSpaceEditPath()).toEqual(true)
      })

      test('returns true for /copilot/spaces/:space_id style paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/123/edit'
        expect(isCopilotSpaceEditPath()).toEqual(true)
      })

      test('returns false for a path with an underscore in the owner', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/test_owner/123/edit'
        expect(isCopilotSpaceEditPath()).toEqual(false)
      })

      test('returns false for a path with just an owner', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/testowner/edit'
        expect(isCopilotSpaceEditPath()).toEqual(false)
      })

      test('returns false for a path with an owner and nonnumerical number', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/testowner/testspace/edit'
        expect(isCopilotSpaceEditPath()).toEqual(false)
      })

      test('returns false for non-matching paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/some/other/path'
        expect(isCopilotSpaceEditPath()).toEqual(false)
      })

      test('returns false for index paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces'
        expect(isCopilotSpaceEditPath()).toEqual(false)
      })

      test('returns false for show space paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/my-org/123'
        expect(isCopilotSpaceEditPath()).toEqual(false)
      })
    })

    describe('isCopilotSpacePath', () => {
      beforeEach(() => {
        // Reset ssrSafeLocation pathname
        ;(ssrSafeLocation as {pathname: string}).pathname = ''
      })

      test('returns true for /copilot/spaces/:owner/:number style paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/testowner/123'
        expect(isCopilotSpacePath()).toEqual(true)
      })

      test('returns true for /copilot/spaces/:space_id style paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/123'
        expect(isCopilotSpacePath()).toEqual(true)
      })

      test('returns false for a path with an underscore in the owner', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/test_owner/123'
        expect(isCopilotSpacePath()).toEqual(false)
      })

      test('returns false for a path with just an owner', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/testowner'
        expect(isCopilotSpacePath()).toEqual(false)
      })

      test('returns false for a path with an owner and nonnumerical number', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/testowner/testspace'
        expect(isCopilotSpacePath()).toEqual(false)
      })

      test('returns false for non-matching paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/some/other/path'
        expect(isCopilotSpacePath()).toEqual(false)
      })

      test('returns false for index paths', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces'
        expect(isCopilotSpacePath()).toEqual(false)
      })
    })

    describe('useRouteSpaceId', () => {
      beforeEach(() => {
        // Reset ssrSafeLocation pathname
        ;(ssrSafeLocation as {pathname: string}).pathname = ''
      })

      test('returns null for non-matching path', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/some/other/path'
        const {result} = renderHook(() => useRouteSpaceId(), {wrapper})
        expect(result.current).toBeNull()
      })

      test('returns id and owner for owner path format', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/testowner/123'
        const {result} = renderHook(() => useRouteSpaceId(), {wrapper})
        expect(result.current).toEqual({
          id: 123,
          owner: 'testowner',
        })
      })

      test('returns just id for space_id path format', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/123'
        const {result} = renderHook(() => useRouteSpaceId(), {wrapper})
        expect(result.current).toEqual({
          id: 123,
        })
      })

      test('returns null for invalid space id', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/invalid'
        const {result} = renderHook(() => useRouteSpaceId(), {wrapper})
        expect(result.current).toBeNull()
      })

      test('returns null for invalid owner/space path', () => {
        ;(ssrSafeLocation as {pathname: string}).pathname = '/copilot/spaces/owner/invalid'
        const {result} = renderHook(() => useRouteSpaceId(), {wrapper})
        expect(result.current).toBeNull()
      })
    })
  })
})

describe('findCustomCopilot', () => {
  // Minimal valid CustomCopilot objects for testing
  const copilotA = getCustomCopilotMock({id: 1, oldId: 1})
  const copilotB = getCustomCopilotMock({id: 2, oldId: 42, owner: 'octocat'})
  const copilotC = getCustomCopilotMock({id: 3, oldId: 3, owner: 'hubber'})

  const copilotList = [copilotA, copilotB, copilotC]

  test('returns undefined if customCopilotId is null', () => {
    expect(findCustomCopilot(copilotList, null)).toBeUndefined()
  })

  test('returns undefined if customCopilotId is undefined', () => {
    expect(findCustomCopilot(copilotList, undefined)).toBeUndefined()
  })

  test('finds copilot by id only (no owner)', () => {
    expect(findCustomCopilot(copilotList, {id: 1})).toBe(copilotA)
  })

  test('finds copilot by id and owner', () => {
    expect(findCustomCopilot(copilotList, {id: 2, owner: 'octocat'})).toBe(copilotB)
  })

  test('finds copilot by oldId when owner is not present in the CustomCopilotId', () => {
    expect(findCustomCopilot(copilotList, {id: 42})).toBe(copilotB)
  })

  test('returns undefined if id matches but owner does not', () => {
    expect(findCustomCopilot(copilotList, {id: 2, owner: 'wrong'})).toBeUndefined()
  })

  test('returns undefined if id matches but only copilot has owner', () => {
    expect(findCustomCopilot(copilotList, {id: 2})).toBeUndefined()
  })

  test('returns undefined if id not found', () => {
    expect(findCustomCopilot(copilotList, {id: 999})).toBeUndefined()
  })
})

describe('getRepositoryFromOrgSearchQuery', () => {
  it('searches for the org and repo name if given', () => {
    const result = getRepositoryFromOrgSearchQuery('github', 'react')
    expect(result).toBe('org:github react in:name archived:false')
  })

  it('returns query with the org and repo name if the query string includes an org', () => {
    const result = getRepositoryFromOrgSearchQuery('github', 'foobar/react')
    expect(result).toBe('org:github react in:name archived:false')
  })

  it('searches just the org if the repo name is empty and there is a slash', () => {
    const result = getRepositoryFromOrgSearchQuery('github', 'myorg/')
    expect(result).toBe('org:github in:name archived:false')
  })

  it('searches just the repo name if no org is given', () => {
    const result = getRepositoryFromOrgSearchQuery('', 'react')
    expect(result).toBe('org: react in:name archived:false')
  })
})
