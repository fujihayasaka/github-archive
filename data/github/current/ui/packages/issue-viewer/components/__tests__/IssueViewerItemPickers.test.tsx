import {act, screen, within} from '@testing-library/react'
import {LABELS} from '../../constants/labels'
import {TEST_IDS} from '../../constants/test-ids'
import {renderIssueViewerTestComponent} from '../../test-utils/components/IssueViewerTestComponent'
import {setupUserEvent} from '@github-ui/react-core/test-utils'

describe('item pickers', () => {
  test('open assignee picker when pressing A', async () => {
    const user = setupUserEvent()
    renderIssueViewerTestComponent({})

    expect(screen.getByTestId(TEST_IDS.issueHeader)).toBeInTheDocument()

    await user.keyboard('a')
    const dialog = within(screen.getByRole('dialog'))

    await act(async () => {
      expect(dialog.getByText('Assign up to 10 people to this issue')).toBeInTheDocument()
      expect(dialog.getByRole('textbox')).toHaveTextContent('')
    })
  })

  test('open label picker when pressing L', async () => {
    renderIssueViewerTestComponent({})
    const user = setupUserEvent()

    expect(screen.getByTestId(TEST_IDS.issueHeader)).toBeInTheDocument()

    await user.keyboard('l')
    const dialog = within(screen.getByRole('dialog'))

    expect(dialog.getByText('Apply labels to this issue')).toBeInTheDocument()

    const input = dialog.getByRole('textbox')
    expect(input).toHaveTextContent('')
  })

  test('open milestone picker when pressing M', async () => {
    renderIssueViewerTestComponent({})
    const user = setupUserEvent()

    expect(screen.getByTestId(TEST_IDS.issueHeader)).toBeInTheDocument()

    await user.keyboard('m')

    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByText('Set milestone')).toBeInTheDocument()

    const input = dialog.getByRole('textbox')
    expect(input).toHaveTextContent('')
  })

  test('open project picker when pressing P', async () => {
    renderIssueViewerTestComponent({})
    const user = setupUserEvent()

    const projectContainer = await screen.findByTestId(TEST_IDS.projectsContainer)
    expect(projectContainer).toBeInTheDocument()

    expect(screen.getByTestId(TEST_IDS.issueHeader)).toBeInTheDocument()

    await user.keyboard('p')

    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByText(LABELS.selectProjects)).toBeInTheDocument()

    const input = dialog.getByRole('textbox')
    expect(input).toHaveTextContent('')
  })
})
