import {screen} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import HiddenDiffPatch from '../HiddenDiffPatch'
import {describe, it, expect, vi} from '@github-ui/tests'

const userEvent = setupUserEvent()
describe('HiddenDiffPatch', () => {
  const onLoadDiff = vi.fn()

  it('renders Load Diff button when not loading', () => {
    render(
      <HiddenDiffPatch onLoadDiff={onLoadDiff} diffAnchor="test-anchor">
        Test Children
      </HiddenDiffPatch>,
    )
    expect(screen.getByText('Load Diff')).toBeInTheDocument()
  })

  it('calls onLoadDiff and shows spinner when Load Diff button is clicked', async () => {
    const {container} = render(
      <HiddenDiffPatch onLoadDiff={onLoadDiff} diffAnchor="test-anchor">
        Test Children
      </HiddenDiffPatch>,
    )
    await userEvent.click(screen.getByText('Load Diff'))
    expect(onLoadDiff).toHaveBeenCalled()
    // eslint-disable-next-line testing-library/no-container, testing-library/no-node-access
    const loadingSpinner = container.querySelector('svg')
    expect(loadingSpinner).toBeInTheDocument()
  })

  it('shows error message and retry link when loading fails', async () => {
    const loadDiff = vi.fn()
    loadDiff.mockRejectedValue(new Error('Async error'))

    render(
      <HiddenDiffPatch onLoadDiff={loadDiff} diffAnchor="test-anchor">
        Test Children
      </HiddenDiffPatch>,
    )
    await userEvent.click(screen.getByText('Load Diff'))
    expect(screen.getByText("The contents of the file couldn't be loaded.")).toBeInTheDocument()
    expect(screen.getByText('Retry')).toBeInTheDocument()
    await userEvent.click(screen.getByText('Retry'))
    expect(loadDiff).toHaveBeenCalled()
  })

  it('renders help link when helpText and helpUrl are provided', () => {
    render(
      <HiddenDiffPatch
        onLoadDiff={onLoadDiff}
        diffAnchor="test-anchor"
        helpText="Help Text"
        helpUrl="https://example.com"
      >
        Test Children
      </HiddenDiffPatch>,
    )
    expect(screen.getByText('Help Text')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Help Text'})).toHaveAttribute('href', 'https://example.com')
  })

  it('renders children content', () => {
    render(
      <HiddenDiffPatch onLoadDiff={onLoadDiff} diffAnchor="test-anchor">
        Test Children
      </HiddenDiffPatch>,
    )
    expect(screen.getByText('Test Children')).toBeInTheDocument()
  })
})
