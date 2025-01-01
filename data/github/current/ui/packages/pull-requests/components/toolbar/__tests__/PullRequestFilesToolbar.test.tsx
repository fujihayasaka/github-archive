import {useTreePane} from '@github-ui/commits/shared/useTreePane'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {render} from '@github-ui/react-core/test-utils'
import {AliveTestProvider} from '@github-ui/use-alive/test-utils'
import {screen} from '@testing-library/react'
import {getFilesRoutePayload} from '../../../test-utils/files-changed/files-mock-data'
import {getPullRequestFilesToolbarMockData} from '../../../test-utils/files-changed/toolbar-mock-data'
import {LivePullRequestFilesToolbar, type PullRequestFilesToolbarProps} from '../PullRequestFilesToolbar'
import {
  mockMarkersData,
  mockUseCommentCountFromMarkersData,
  mockUseMarkersData,
  mockUseMarkersDataWithSelectThreadAndAnnotationIDs,
} from '../../../test-utils/files-changed/markers-mock-data'
import {
  defaultMockFileFilterProps,
  TestFileFilterComponent,
} from '../../../test-utils/files-changed/file-filter-mock-data'
import {getHeaderPageData} from '../../../test-utils/header-mock-data'
import {useHeaderPageData} from '../../../page-data/loaders/use-header-page-data'

jest.mock('../../../page-data/loaders/use-markers-data')
jest.mock('../../../page-data/loaders/use-header-page-data')

beforeEach(() => {
  mockUseMarkersData({
    isSuccess: true,
    data: mockMarkersData,
  })

  mockUseMarkersDataWithSelectThreadAndAnnotationIDs({
    isSuccess: true,
    data: {
      threads: {},
      annotations: {},
    },
  })

  mockUseCommentCountFromMarkersData({
    isSuccess: true,
    data: 0,
  })
  ;(useHeaderPageData as jest.Mock).mockReturnValue({
    isSuccess: true,
    data: {
      aliveChannel,
      bannersData,
      pullRequest,
      repository,
      urls,
      user,
    },
  })
})

const {bannersData, urls, user, aliveChannel, pullRequest, repository} = getHeaderPageData()
function TestComponent({toolbarProps}: {toolbarProps?: Partial<PullRequestFilesToolbarProps>}) {
  const {repository: payloadRepository} = getFilesRoutePayload()
  const toolbarPayload = getPullRequestFilesToolbarMockData()
  const {treeToggleElement} = useTreePane('test-id', true)

  return (
    <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
      <AliveTestProvider>
        <LivePullRequestFilesToolbar
          {...toolbarPayload}
          repository={payloadRepository}
          {...toolbarProps}
          treeToggleElement={treeToggleElement}
          fileFilter={<TestFileFilterComponent {...defaultMockFileFilterProps} />}
          aliveChannel={aliveChannel}
          bannersData={bannersData}
          urls={urls}
          user={user}
        />
      </AliveTestProvider>
    </PageDataContextProvider>
  )
}
beforeEach(() => {
  mockUseMarkersData({
    isSuccess: true,
    data: mockMarkersData,
  })
})

test('Renders the PullRequestFilesToolbar', async () => {
  render(<TestComponent />)

  // Expand Button - 1 for desktop provided by useTreePane
  expect(screen.getAllByRole('button', {name: 'Expand file tree'})).toHaveLength(1)

  // Viewed File Progress
  expect(screen.getByText('viewed')).toBeInTheDocument()
  // We need to use element type and textContent mapper here as the "# / # viewed" is wrapped in a parent <SPAN> element and broken up by multiple children <span> elements.
  expect(
    screen.getByText((_, element) => element?.nodeName === 'SPAN' && element.textContent === '1 / 2 viewed'),
  ).toBeInTheDocument()

  // Open Comments Side Panel Button
  expect(screen.getByLabelText('Open comments side panel')).toBeInTheDocument()

  // Open Alerts Side Panel Button
  expect(screen.getByLabelText('Open alerts side panel')).toBeInTheDocument()

  // Review Menu
  expect(screen.getByText('Submit review')).toBeInTheDocument()
})

function getDivider() {
  return screen
    .getAllByRole('generic')
    .find(
      el =>
        el.classList.contains('border-left') &&
        el.classList.contains('mx-1') &&
        el.classList.contains('d-block') &&
        el.style.width === '1px' &&
        el.style.height === '28px',
    )
}

test('shows divider when shouldShowViewedFilesCount is true', () => {
  render(<TestComponent toolbarProps={{shouldShowViewedFilesCount: true, isFileTreeExpanded: true}} />)
  expect(getDivider()).toBeInTheDocument()
})

test('shows divider when isFileTreeExpanded is false', () => {
  render(<TestComponent toolbarProps={{shouldShowViewedFilesCount: false, isFileTreeExpanded: false}} />)
  expect(getDivider()).toBeInTheDocument()
})

test('does not show divider when shouldShowViewedFilesCount is false and isFileTreeExpanded is true', () => {
  render(<TestComponent toolbarProps={{shouldShowViewedFilesCount: false, isFileTreeExpanded: true}} />)
  expect(getDivider()).toBeUndefined()
})
