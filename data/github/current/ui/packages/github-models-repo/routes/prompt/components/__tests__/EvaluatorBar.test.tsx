import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {initialPromptCompareState, PromptCompareStateProvider} from '../../contexts/PromptCompareStateContext'
import type {CompareState} from '../../prompt-compare-state'
import {EvaluatorBar} from '../EvaluatorBar'

describe('EvaluatorBar', () => {
  it('renders empty state', () => {
    render(<EvaluatorBar />)

    expect(screen.getByRole('button', {name: 'Add evaluator'})).toBeInTheDocument()
  })

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
        <EvaluatorBar />
      </PromptCompareStateProvider>,
    )

    expect(screen.getByRole('button', {name: 'Add evaluator'})).toBeInTheDocument()
    expect(screen.getByText('eval 1')).toBeInTheDocument()
    expect(screen.getByText('eval 2')).toBeInTheDocument()
  })
})
