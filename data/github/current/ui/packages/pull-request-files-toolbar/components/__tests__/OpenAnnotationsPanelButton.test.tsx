import type {DiffAnnotation} from '@github-ui/conversations'
import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {OpenAnnotationsPanelButton} from '../OpenAnnotationsPanelButton'
import {buildAnnotation} from '@github-ui/conversations/test-utils'

jest.mock('@github-ui/conversations/ensure-previous-active-dialog-is-closed')
const ensurePreviousActiveDialogIsClosedMock = jest.mocked(ensurePreviousActiveDialogIsClosed)

const mockAnnotation = buildAnnotation({})

function TestComponent({
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  annotations = [],
}: {
  annotations?: DiffAnnotation[]
}) {
  return <OpenAnnotationsPanelButton annotations={annotations} />
}

test('renders if there is at least 1 annotation', () => {
  render(<TestComponent annotations={[mockAnnotation]} />)

  expect(screen.getByRole('button', {name: 'Open annotations side panel'})).toBeVisible()
})

test('does not render if there is no annotations', () => {
  render(<TestComponent annotations={[]} />)

  expect(screen.queryByRole('button', {name: 'Open annotations side panel'})).toBeNull()
})

test('ensures that previous active dialog is closed when clicked', async () => {
  const {user} = render(<TestComponent annotations={[mockAnnotation]} />)

  await user.click(screen.getByRole('button', {name: 'Open annotations side panel'}))
  expect(ensurePreviousActiveDialogIsClosedMock).toHaveBeenCalled()
})
