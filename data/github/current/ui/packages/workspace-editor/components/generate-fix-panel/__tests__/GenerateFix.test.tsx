import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {getGeneratedFix, getGenerativeTaskData, getWorkspaceEditorRoutePayload} from '../../../test-utils/mock-data'
import {TestComponentWrapper} from '../../../test-utils/TestComponentWrapper'
import {GENERATE_A_FIX_FLAG, GenerateFix} from '../GenerateFix'

const mockUseGenerateFixQuery = jest.fn()
jest.mock('../../../hooks/use-generate-fix-query', () => ({
  useGenerateFixQuery: () => mockUseGenerateFixQuery(),
}))

const useClassifyCommentsMock = jest.fn()
jest.mock('../../../hooks/use-classify-comments', () => ({
  useClassifyComments: () => useClassifyCommentsMock(),
}))

const mockUseFeatureFlags = jest.fn().mockReturnValue({})
const mockUseFeatureFlag = jest.fn().mockReturnValue(true)
const mockGenerateFixFlag = jest.fn().mockReturnValue(true)

jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlags: () => mockUseFeatureFlags({[GENERATE_A_FIX_FLAG]: true}),
  useFeatureFlag: (flag: string) => {
    if (flag === GENERATE_A_FIX_FLAG) {
      return mockGenerateFixFlag()
    }
    return mockUseFeatureFlag()
  },
}))
function TestComponent({generateAFixEnabled = true}) {
  mockGenerateFixFlag.mockReturnValue(generateAFixEnabled)

  return (
    <TestComponentWrapper>
      <GenerateFix suggestionsForPagination={[]} focusedGenerativeTask={getGenerativeTaskData()} />
    </TestComponentWrapper>
  )
}

beforeEach(() => {
  mockUseGenerateFixQuery.mockImplementation(() => {
    return {
      generatedFix: getGeneratedFix(),
      isFetching: false,
      refetch: () => {},
      isError: false,
    }
  })

  useClassifyCommentsMock.mockImplementation(() => {
    return {
      commentClassification: {
        actionable: true,
        reasoning: 'This is a comment about the code',
      },
      isFetching: false,
      isError: false,
    }
  })
})

afterEach(() => {
  localStorage.clear()
  jest.clearAllMocks()
})

describe('GenerateFix', () => {
  test('renders generate fix panel when flag disabled, without Copilot response', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()

    render(<TestComponent generateAFixEnabled={false} />, {
      routePayload,
    })

    const firstComment = await screen.findByText('comment 1 body')
    expect(firstComment).toBeVisible()
    expect(screen.queryByText('Copilot')).not.toBeInTheDocument()
    expect(screen.getByText('monalisa')).toBeVisible()
    expect(screen.getByText('comment 2 body')).toBeVisible()
    expect(screen.getByText('contributor')).toBeVisible()
    expect(screen.getByText('comment 3 body')).toBeVisible()
    expect(screen.getByText('rando')).toBeVisible()
    expect(screen.queryByText('Outdated')).not.toBeInTheDocument()
  })

  test('renders generate fix panel', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()

    const {user} = render(<TestComponent />, {
      routePayload,
    })

    const firstComment = await screen.findByText('comment 1 body')
    expect(firstComment).toBeVisible()
    expect(screen.getByText('monalisa')).toBeVisible()
    await user.click(screen.getByText('2 replies'))
    expect(screen.getByText('comment 2 body')).toBeVisible()
    expect(screen.getByText('contributor')).toBeVisible()
    expect(screen.getByText('comment 3 body')).toBeVisible()
    expect(screen.getByText('rando')).toBeVisible()
    expect(screen.queryByText('Outdated')).not.toBeInTheDocument()
  })

  test('generating fix busy state', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()

    const {user} = render(<TestComponent />, {
      routePayload,
    })

    expect(await screen.findByText('comment 1 body')).toBeVisible()
    expect(await screen.findByText('Copilot')).toBeVisible()
    expect(screen.getByText('monalisa')).toBeVisible()

    // replies should collapse into a single line
    expect(screen.queryByText('comment 2 body')).not.toBeInTheDocument()
    expect(screen.queryByText('contributor')).not.toBeInTheDocument()
    const repliesToggle = screen.getByText('2 replies')
    expect(repliesToggle).toBeVisible()
    await user.click(repliesToggle)

    // replies can be toggled in and out of view
    expect(screen.getByText('comment 2 body')).toBeVisible()
    expect(screen.getByText('contributor')).toBeVisible()
    await user.click(repliesToggle)
    expect(screen.queryByText('comment 2 body')).not.toBeInTheDocument()
    expect(screen.queryByText('contributor')).not.toBeInTheDocument()
  })

  test('generated fix is displayed as a toggleable diff', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()

    const {user} = render(<TestComponent />, {
      routePayload,
    })

    const copilot = await screen.findByText('Copilot')
    expect(copilot).toBeVisible()
    expect(await screen.findByText('This is the original line')).toBeVisible()
    expect(screen.getByText('This is the new line')).toBeVisible()
    expect(screen.getByText('Another new line added')).toBeVisible()

    const collapseButton = screen.getByLabelText('collapse diff: typescript.ts')
    await user.click(collapseButton)
    expect(screen.queryByText('This is the original line')).not.toBeInTheDocument()
    expect(screen.queryByText('This is the new line')).not.toBeInTheDocument()
    expect(screen.queryByText('Another new line added')).not.toBeInTheDocument()

    await user.click(collapseButton)
    expect(screen.getByText('This is the original line')).toBeVisible()
  })

  test('comments are classified as not having a fix', async () => {
    useClassifyCommentsMock.mockImplementation(() => {
      return {
        commentClassification: {
          actionable: false,
          reasoning: 'This is not a comment about the code',
        },
        isFetching: false,
      }
    })

    const routePayload = getWorkspaceEditorRoutePayload()

    render(<TestComponent />, {
      routePayload,
    })

    expect(await screen.findByText('comment 1 body')).toBeVisible()
    expect(screen.getByText('monalisa')).toBeVisible()
    expect(screen.getByText('No suggestions for this comment.')).toBeVisible()
    expect(screen.queryByText('Apply')).not.toBeInTheDocument()
  })

  test('fix is outdated', async () => {
    mockUseGenerateFixQuery.mockImplementation(() => {
      return {
        generatedFix: getGeneratedFix({commentsVersion: 'different-etag'}),
        isFetching: false,
        refetch: () => {},
      }
    })

    const routePayload = getWorkspaceEditorRoutePayload()

    render(<TestComponent />, {
      routePayload,
    })

    expect(await screen.findByText('comment 1 body')).toBeVisible()
    expect(screen.getByText('monalisa')).toBeVisible()
    expect(screen.getByText('Outdated')).toBeVisible()
  })

  test('error while fetching the comment classification', async () => {
    // There's an error parsing the CSS stylesheet that is logged to the console
    // in test. I don't see this in dev, so I'm not sure what's happening here.
    jest.spyOn(console, 'error').mockImplementation()
    useClassifyCommentsMock.mockImplementation(() => {
      return {
        commentClassification: {
          actionable: false,
          reasoning: 'This is not a comment about the code',
        },
        isFetching: false,
        isError: true,
      }
    })
    const routePayload = getWorkspaceEditorRoutePayload()

    const {user} = render(<TestComponent />, {
      routePayload,
    })

    const firstComment = await screen.findByText('comment 1 body')
    expect(firstComment).toBeVisible()
    expect(screen.getByText('monalisa')).toBeVisible()
    await user.click(screen.getByText('2 replies'))
    expect(screen.getByText('comment 2 body')).toBeVisible()
    expect(screen.getByText('contributor')).toBeVisible()
    expect(screen.getByText('comment 3 body')).toBeVisible()
    expect(screen.getByText('rando')).toBeVisible()
    expect(screen.getByText('Unexpected error occurred')).toBeVisible()
  })

  test('error while fetching the suggested fix', async () => {
    // There's an error parsing the CSS stylesheet that is logged to the console
    // in test. I don't see this in dev, so I'm not sure what's happening here.
    jest.spyOn(console, 'error').mockImplementation()
    mockUseGenerateFixQuery.mockImplementation(() => {
      return {
        generatedFix: getGeneratedFix(),
        isFetching: false,
        isError: true,
        refetch: () => {},
      }
    })
    const routePayload = getWorkspaceEditorRoutePayload()

    const {user} = render(<TestComponent />, {
      routePayload,
    })

    const firstComment = await screen.findByText('comment 1 body')
    expect(firstComment).toBeVisible()
    expect(screen.getByText('monalisa')).toBeVisible()
    await user.click(screen.getByText('2 replies'))
    expect(screen.getByText('comment 2 body')).toBeVisible()
    expect(screen.getByText('contributor')).toBeVisible()
    expect(screen.getByText('comment 3 body')).toBeVisible()
    expect(screen.getByText('rando')).toBeVisible()
    expect(screen.getByText('Unexpected error occurred')).toBeVisible()
  })
})
