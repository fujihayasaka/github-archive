import type {DiffAnnotation} from '@github-ui/conversations'
import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {OpenAlertsPanelButton} from '../OpenAlertsPanelButton'
import {buildAnnotation} from '@github-ui/conversations/test-utils'
import {mockMarkersData, mockUseMarkersData} from '../../../test-utils/files-changed/markers-mock-data'
import type {PageLimits} from '../../../page-data/payloads/files'
import {getFilesRoutePayload} from '../../../test-utils/files-changed/files-mock-data'

jest.mock('@github-ui/conversations/ensure-previous-active-dialog-is-closed')
jest.mock('../../../page-data/loaders/use-markers-data')

const ensurePreviousActiveDialogIsClosedMock = jest.mocked(ensurePreviousActiveDialogIsClosed)

const mockAnnotation = buildAnnotation({})

function TestComponent({
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  annotations = [],
  pageLimits,
}: {
  annotations?: DiffAnnotation[]
  pageLimits: PageLimits
}) {
  const annotationsById = annotations.reduce(
    (acc, annotation) => {
      acc[annotation.databaseId] = annotation
      return acc
    },
    {} as Record<number, DiffAnnotation>,
  )

  mockUseMarkersData({
    isSuccess: true,
    data: {...mockMarkersData, annotations: annotationsById},
  })

  return <OpenAlertsPanelButton basePath="" pageLimits={pageLimits} />
}

test('renders if there is at least 1 annotation', () => {
  render(<TestComponent annotations={[mockAnnotation]} pageLimits={getFilesRoutePayload().pageLimits} />)

  expect(screen.getByRole('button', {name: 'Open alerts side panel'})).toBeVisible()
})

test('does not render if there is no annotations', () => {
  render(<TestComponent annotations={[]} pageLimits={getFilesRoutePayload().pageLimits} />)

  expect(screen.queryByRole('button', {name: 'Open alerts side panel'})).toBeNull()
})

test('ensures that previous active dialog is closed when clicked', async () => {
  const {user} = render(<TestComponent annotations={[mockAnnotation]} pageLimits={getFilesRoutePayload().pageLimits} />)

  await user.click(screen.getByRole('button', {name: 'Open alerts side panel'}))
  expect(ensurePreviousActiveDialogIsClosedMock).toHaveBeenCalled()
})

test('renders warning banner if annotations limit is exceeded', async () => {
  const limits: PageLimits = {
    ...getFilesRoutePayload().pageLimits,
    annotationsLimit: 100,
    annotationsLimitExceeded: true,
    filesLimit: 300,
    filesLimitExceeded: false,
    reviewThreadsLimit: 100,
    reviewThreadsLimitExceeded: false,
  }
  const {user} = render(<TestComponent annotations={[mockAnnotation]} pageLimits={limits} />)

  await user.click(screen.getByRole('button', {name: 'Open alerts side panel'}))
  expect(screen.getByText('Only the first 100 alerts are currently being shown.')).toBeInTheDocument()
})

test('does not render warning banner if annotations limit is not exceeded', async () => {
  const limits: PageLimits = {
    ...getFilesRoutePayload().pageLimits,
    annotationsLimit: 100,
    annotationsLimitExceeded: false,
    filesLimit: 300,
    filesLimitExceeded: false,
    reviewThreadsLimit: 100,
    reviewThreadsLimitExceeded: false,
  }
  const {user} = render(<TestComponent annotations={[mockAnnotation]} pageLimits={limits} />)

  await user.click(screen.getByRole('button', {name: 'Open alerts side panel'}))
  expect(screen.queryByText('Only the first 100 alerts are currently being shown.')).not.toBeInTheDocument()
})

test('does not render warning banner if pageLimits is undefined', async () => {
  const {user} = render(<TestComponent annotations={[mockAnnotation]} pageLimits={getFilesRoutePayload().pageLimits} />)

  await user.click(screen.getByRole('button', {name: 'Open alerts side panel'}))
  expect(screen.queryByText('Only the first 100 alerts are currently being shown.')).not.toBeInTheDocument()
})
