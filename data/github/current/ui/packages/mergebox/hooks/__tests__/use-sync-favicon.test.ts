import {renderHook} from '@testing-library/react'
import {resetFavicon, updateFaviconByVariant} from '@github-ui/favicon'
import {useSyncFavicon} from '../use-sync-favicon'
import {
  checksSectionFailedState,
  checksSectionNoChecksState,
  checksSectionPassingState,
  checksSectionPendingState,
} from '../../test-utils/mocks/checks-section-mocks'

jest.mock('@github-ui/favicon', () => ({
  resetFavicon: jest.fn(),
  updateFaviconByVariant: jest.fn(),
}))

const NO_CHECKS_STATUS_ROLLUP = checksSectionNoChecksState.statusRollup
const PASSED_STATUS_ROLLUP = checksSectionPassingState.statusRollup
const FAILED_STATUS_ROLLUP = checksSectionFailedState.statusRollup
const PENDING_STATUS_ROLLUP = checksSectionPendingState.statusRollup

describe('useSyncFavicon', () => {
  beforeEach(() => {
    jest.resetAllMocks()
  })

  it('should reset favicon if there are no checks', () => {
    renderHook(() => useSyncFavicon(NO_CHECKS_STATUS_ROLLUP))

    expect(resetFavicon).toHaveBeenCalled()
    expect(updateFaviconByVariant).not.toHaveBeenCalled()
  })

  it('should update favicon to success when combinedState is PASSED', () => {
    renderHook(() => useSyncFavicon(PASSED_STATUS_ROLLUP))

    expect(updateFaviconByVariant).toHaveBeenCalledWith('success')
    expect(resetFavicon).not.toHaveBeenCalled()
  })

  it('should update favicon to pending when combinedState is PENDING', () => {
    renderHook(() => useSyncFavicon(PENDING_STATUS_ROLLUP))

    expect(updateFaviconByVariant).toHaveBeenCalledWith('pending')
    expect(resetFavicon).not.toHaveBeenCalled()
  })

  it('should update favicon to failure when combinedState is FAILED', () => {
    renderHook(() => useSyncFavicon(FAILED_STATUS_ROLLUP))

    expect(updateFaviconByVariant).toHaveBeenCalledWith('failure')
    expect(resetFavicon).not.toHaveBeenCalled()
  })

  it('should update favicon on subsequent combinedState changes', () => {
    const {rerender} = renderHook(props => useSyncFavicon(props), {
      initialProps: PENDING_STATUS_ROLLUP,
    })

    expect(updateFaviconByVariant).toHaveBeenCalledWith('pending')

    rerender(PASSED_STATUS_ROLLUP)

    expect(updateFaviconByVariant).toHaveBeenCalledWith('success')
  })
})
