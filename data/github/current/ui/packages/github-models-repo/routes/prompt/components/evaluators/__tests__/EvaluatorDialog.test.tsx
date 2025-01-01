import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import type {EvaluatorCfg} from '../../../evals-sdk/config'
import type {EvaluatorTemplate} from '../../../evaluator-template'
import {type PromptCompareManager, PromptCompareManagerContext} from '../../../prompt-compare-manager'
import {mockResizeObserver} from '../../../../../test-utils/mock-data'
import {EvaluatorDialog} from '../EvaluatorDialog'

const onClose = jest.fn().mockName('onClose')
const evalsAddEvaluator = jest.fn().mockName('evalsAddEvaluator')
const evalsUpdateEvaluator = jest.fn().mockName('evalsUpdateEvaluator')

describe('EvaluatorDialog', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders without a template', async () => {
    const evaluator: EvaluatorCfg = {name: '', string: {}}

    const {user} = render(<EvaluatorDialog onClose={onClose} evaluator={evaluator} />)

    const dialog = screen.getByRole('dialog', {name: 'Edit test criteria'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Edit test criteria'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Update'})).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: 'Name *'})).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: 'Value *'})).toBeInTheDocument()
    const operationSelect = within(dialog).getByRole('combobox', {name: 'Operation'})
    expect(operationSelect).toBeInTheDocument()
    expect(within(operationSelect).getByRole('option', {name: 'contains'})).toBeInTheDocument()
    expect(within(operationSelect).getByRole('option', {name: 'startsWith'})).toBeInTheDocument()
    expect(within(operationSelect).getByRole('option', {name: 'endsWith'})).toBeInTheDocument()
    expect(within(dialog).getByRole('checkbox', {name: 'Case-sensitive'})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
    expect(evalsAddEvaluator).not.toHaveBeenCalled()
    expect(evalsUpdateEvaluator).not.toHaveBeenCalled()
  })

  it('renders with a template', async () => {
    const template: EvaluatorTemplate = {
      displayName: 'Similarity',
      description: 'Evaluates similarity score for QA scenario',
      category: 'quality',
      readonly: true,
      configTemplate: {name: 'Similarity', uses: 'github/similarity'},
    }
    const evaluatorIndex = 1

    const {user} = render(
      <EvaluatorDialog
        evaluatorIndex={evaluatorIndex}
        onClose={onClose}
        evaluator={template.configTemplate}
        template={template}
      />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Edit test criteria'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Edit test criteria'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const submitButton = within(dialog).getByRole('button', {name: 'Update'})
    expect(submitButton).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: 'Name *'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()

    await user.click(submitButton)

    expect(evalsUpdateEvaluator).toHaveBeenCalledTimes(1)
    expect(evalsUpdateEvaluator).toHaveBeenCalledWith(evaluatorIndex, template.configTemplate)
    expect(onClose).toHaveBeenCalledTimes(1)
    expect(evalsAddEvaluator).not.toHaveBeenCalled()
  })

  it('allows adding an evaluator', async () => {
    const template: EvaluatorTemplate = {
      displayName: 'Relevance',
      description: 'Evaluates relevance score for QA scenario',
      category: 'relevance',
      configTemplate: {name: 'Relevance', uses: 'github/relevance'},
    }

    const {user} = render(<EvaluatorDialog onClose={onClose} template={template} />)

    const dialog = screen.getByRole('dialog', {name: 'Add test criteria'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Add test criteria'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const submitButton = within(dialog).getByRole('button', {name: 'Add'})
    expect(submitButton).toBeInTheDocument()
    const nameInput = within(dialog).getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()

    await user.type(nameInput, 'foo')
    await user.click(submitButton)

    expect(onClose).toHaveBeenCalledTimes(1)
    expect(evalsAddEvaluator).toHaveBeenCalledTimes(1)
    expect(evalsAddEvaluator).toHaveBeenCalledWith({
      config: {...template.configTemplate, name: `${template.configTemplate.name}foo`},
    })
    expect(evalsUpdateEvaluator).not.toHaveBeenCalled()
  })
})

function render(component: JSX.Element) {
  const manager = {} as PromptCompareManager
  manager.evalsAddEvaluator = evalsAddEvaluator
  manager.evalsUpdateEvaluator = evalsUpdateEvaluator

  return htmlRender(
    <PromptCompareManagerContext.Provider value={manager}>{component}</PromptCompareManagerContext.Provider>,
  )
}
