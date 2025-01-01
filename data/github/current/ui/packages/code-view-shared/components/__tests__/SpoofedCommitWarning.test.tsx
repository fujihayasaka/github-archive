import {resetMemoizeFetchJSON} from '@github-ui/use-latest-commit'
import {render} from '@github-ui/react-core/test-utils'
import {SpoofedCommitWarning, SpoofedCommitWarningBanner} from '../SpoofedCommitWarning'
import {act, screen} from '@testing-library/react'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import type {FileTreePagePayload} from '@github-ui/code-view-types'
import {testTreePayload} from '../../__tests__/test-helpers'
import {FilesPageInfoProvider} from '../../contexts/FilesPageInfoContext'
import {mockFetch} from '@github-ui/mock-fetch'
import {latestCommitDataWithStatus} from '@github-ui/use-latest-commit/sample-data'

beforeEach(() => {
  resetMemoizeFetchJSON()
})

const renderSpoofedCommitWarning = (payload: FileTreePagePayload) => {
  return render(
    <CurrentRepositoryProvider repository={payload.repo}>
      <FilesPageInfoProvider action="tree" copilotAccessAllowed={false} path={payload.path} refInfo={payload.refInfo}>
        <SpoofedCommitWarning />
      </FilesPageInfoProvider>
    </CurrentRepositoryProvider>,
  )
}

describe('SpoofedCommitWarning', () => {
  test('does not show warning when commit is not spoofed', async () => {
    renderSpoofedCommitWarning(testTreePayload)

    // the banner is not present when the component is first rendered and the request is pending
    expect(screen.queryByTestId('spoofed-commit-warning-banner')).not.toBeInTheDocument()

    const commitData = latestCommitDataWithStatus
    await act(() => mockFetch.resolvePendingRequest('/monalisa/smile/latest-commit/main/src/app', commitData))

    // the banner is not present when the request is resolved and the commit is not spoofed
    expect(screen.queryByTestId('spoofed-commit-warning-banner')).not.toBeInTheDocument()
  })

  test('shows warning when commit is spoofed', async () => {
    renderSpoofedCommitWarning(testTreePayload)

    const commitData = latestCommitDataWithStatus
    commitData.isSpoofed = true
    await act(() => mockFetch.resolvePendingRequest('/monalisa/smile/latest-commit/main/src/app', commitData))

    // the banner is present when the request is resolved and the commit is spoofed
    expect(screen.getByTestId('spoofed-commit-warning-banner')).toBeInTheDocument()
  })
})

describe('SpoofedCommitWarningBanner', () => {
  test('warning banner can be displayed without hooks', async () => {
    render(<SpoofedCommitWarningBanner />)

    // the banner is present when the banner component is rendered
    expect(screen.getByTestId('spoofed-commit-warning-banner')).toBeInTheDocument()
  })
})
