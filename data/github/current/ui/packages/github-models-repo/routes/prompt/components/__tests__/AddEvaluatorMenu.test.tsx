import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {sendEvent} from '../../../../utils/send-event'
import {mockResizeObserver} from '../../../../test-utils/mock-data'
import {AddEvaluatorMenu} from '../AddEvaluatorMenu'
import {EvaluatorTemplates} from '../../evaluators'
import {AddEvaluatorSelectionClicked} from '../../types'

jest.mock('../../../../utils/send-event', () => {
  return {
    sendEvent: jest.fn(),
  }
})

const onSelectTemplate = jest.fn().mockName('onSelectTemplate')

describe('AddEvaluatorMenu', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders', async () => {
    const {user} = render(<AddEvaluatorMenu totalEvaluators={0} onSelectTemplate={onSelectTemplate} />)

    const menuToggle = screen.getByRole('button', {name: 'Add evaluator'})
    expect(menuToggle).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Add evaluator'})).not.toBeInTheDocument()

    await user.click(menuToggle)

    const menu = screen.getByRole('menu', {name: 'Add evaluator'})
    expect(menu).toBeInTheDocument()
    const customGroup = within(menu).getByRole('group', {name: 'Custom'})
    expect(customGroup).toBeInTheDocument()
    expect(within(customGroup).getByRole('menuitem', {name: 'String check'})).toBeInTheDocument()
    expect(within(customGroup).getByRole('menuitem', {name: 'Custom prompt'})).toBeInTheDocument()
    const qualityGroup = within(menu).getByRole('group', {name: 'Quality'})
    expect(qualityGroup).toBeInTheDocument()
    expect(within(qualityGroup).getByRole('menuitem', {name: 'Similarity'})).toBeInTheDocument()
    const relevanceGroup = within(menu).getByRole('group', {name: 'Relevance'})
    expect(relevanceGroup).toBeInTheDocument()
    expect(within(relevanceGroup).getByRole('menuitem', {name: 'Relevance'})).toBeInTheDocument()
    expect(within(relevanceGroup).getByRole('menuitem', {name: 'Groundedness'})).toBeInTheDocument()
    expect(onSelectTemplate).not.toHaveBeenCalled()
    expect(sendEvent).not.toHaveBeenCalled()
  })

  it.each(EvaluatorTemplates)('emits analytics event on $displayName selection', async evaluatorTemplate => {
    const {user} = render(<AddEvaluatorMenu totalEvaluators={1} onSelectTemplate={onSelectTemplate} />)

    await user.click(screen.getByRole('button', {name: 'Add evaluator'}))
    await user.click(screen.getByRole('menuitem', {name: evaluatorTemplate.displayName}))

    expect(onSelectTemplate).toHaveBeenCalledTimes(1)
    expect(onSelectTemplate).toHaveBeenCalledWith(evaluatorTemplate)
    expect(sendEvent).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledWith(AddEvaluatorSelectionClicked, {
      evaluator: evaluatorTemplate.displayName,
      category: evaluatorTemplate.category ?? 'custom',
      totalEvaluators: 1,
    })
  })
})
