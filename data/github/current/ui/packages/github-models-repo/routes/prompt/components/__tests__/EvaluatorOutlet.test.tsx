import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {initialPromptCompareState, PromptCompareStateProvider} from '../../contexts/PromptCompareStateContext'
import type {CompareState} from '../../prompt-compare-state'
import {EvaluatorOutlet} from '../EvaluatorOutlet'

describe('EvaluatorOutlet', () => {
  it('renders evaluators', () => {
    const state = initialPromptCompareState([], {
      compare: {
        evaluators: [
          {
            config: {
              name: 'eval 1',
            },
          },
          {
            config: {
              name: 'eval 2',
            },
          },
        ],
      } as CompareState,
    })

    render(
      <PromptCompareStateProvider state={state}>
        <EvaluatorOutlet />
      </PromptCompareStateProvider>,
    )

    expect(screen.getByText('eval 1')).toBeInTheDocument()
    expect(screen.getByText('eval 2')).toBeInTheDocument()
  })

  it('opens a dialog to edit', async () => {
    const state = initialPromptCompareState([], {
      compare: {
        evaluators: [
          {
            config: {
              name: 'eval 1',
            },
          },
          {
            config: {
              name: 'eval 2',
            },
          },
        ],
      } as CompareState,
    })

    const {user} = render(
      <PromptCompareStateProvider state={state}>
        <EvaluatorOutlet />
      </PromptCompareStateProvider>,
    )

    const edit = screen.getByRole('button', {name: /^eval 1/})

    await user.click(edit)

    const editDialog = screen.getByRole('dialog', {name: 'Edit test criteria'})
    expect(editDialog).toBeInTheDocument()

    expect(within(editDialog).getByLabelText(/Name/)).toHaveValue('eval 1')
  })

  it('does not render edit button for readonly evaluators', async () => {
    const state = initialPromptCompareState([], {
      compare: {
        evaluators: [
          {
            config: {
              name: 'eval 1',
            },
            readonly: true,
          },
          {
            config: {
              name: 'eval 2',
            },
          },
        ],
      } as CompareState,
    })

    const {user} = render(
      <PromptCompareStateProvider state={state}>
        <EvaluatorOutlet />
      </PromptCompareStateProvider>,
    )

    expect(screen.queryByRole('button', {name: 'eval 1'})).toBeNull()
    expect(screen.getByRole('button', {name: /^eval 2/})).toBeInTheDocument()

    // clicking eval1, even if its not a button should not do anything
    const eval1 = screen.getByText('eval 1')
    await user.click(eval1)

    expect(screen.queryByRole('dialog', {name: 'Edit test criteria'})).toBeNull()
  })
})
