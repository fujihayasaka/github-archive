import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {getWorkspaceEditorRoutePayload} from '../../../test-utils/mock-data'
import {TestComponentWrapper} from '../../../test-utils/TestComponentWrapper'
import {type SuggestionCommentData, TaskTypes} from '../../../utilities/workspace-editor-types'
import {Suggestions} from '../../Suggestions'

function TestComponent({suggestions}: {suggestions: SuggestionCommentData}) {
  return (
    <TestComponentWrapper>
      <Suggestions setSuggestionsForPagination={() => {}} onTaskSelected={() => {}} suggestions={suggestions} />
    </TestComponentWrapper>
  )
}

afterEach(() => {
  localStorage.clear()
  jest.clearAllMocks()
})

describe('Suggestions', () => {
  test('renders suggestions view', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    const repo = routePayload.repo
    localStorage.setItem(`hadron-editor-suggestions-dismissed/${repo.ownerLogin}/${repo.name}/1`, JSON.stringify([4]))
    const suggestions: SuggestionCommentData = {
      ['1']: {
        path: 'path/to/file',
        lineNumber: 1,
        sourceId: 1,
        type: TaskTypes.Suggestion,
        outdated: false,
        author: {
          displayLogin: 'author',
          avatarUrl: 'avatar-url',
        },
      },
      ['2']: {
        path: 'path/to/file',
        lineNumber: 6,
        sourceId: 2,
        type: TaskTypes.Suggestion,
        outdated: false,
        author: {
          displayLogin: 'author',
          avatarUrl: 'avatar-url',
        },
        startLineNumber: 2,
      },
      ['3']: {
        path: 'path/to/file',
        lineNumber: 1,
        sourceId: 3,
        type: TaskTypes.Generative,
        outdated: false,
        author: {
          displayLogin: 'author',
          avatarUrl: 'avatar-url',
        },
      },
      ['4']: {
        path: 'path/to/file',
        lineNumber: 4,
        sourceId: 4,
        type: TaskTypes.Suggestion,
        outdated: false,
        author: {
          displayLogin: 'author',
          avatarUrl: 'avatar-url',
        },
        startLineNumber: 1,
      },
      ['5']: {
        path: 'path/to/file',
        lineNumber: 1,
        sourceId: 5,
        type: TaskTypes.Autofix,
        outdated: false,
        author: {
          displayLogin: 'Autofix',
          avatarUrl: 'avatar-url',
        },
      },
    }

    const {user} = render(<TestComponent suggestions={suggestions} />, {
      routePayload,
    })

    expect(screen.getByText('2 suggested code changes')).toBeInTheDocument()
    expect(screen.getByText('1 comment thread')).toBeInTheDocument()
    expect(screen.getByText('1 Copilot Autofix')).toBeInTheDocument()

    expect(screen.getByText('Suggestion from @author on file:1')).toBeInTheDocument()
    expect(screen.getByText('Suggestion from @author on file:2-6')).toBeInTheDocument()
    expect(screen.getByText('Suggestion from @Autofix')).toBeInTheDocument()
    expect(screen.getByText('Thread by @author on file:1')).toBeInTheDocument()
    expect(screen.queryByText('Suggestion from @author on file:1-4')).not.toBeInTheDocument()

    // groups can be toggled in and out of view
    const dismissedButton = screen.getByText('1 dismissed')
    await user.click(dismissedButton)
    expect(screen.getByText('Suggestion from @author on file:1-4')).toBeInTheDocument()

    await user.click(dismissedButton)
    expect(screen.queryByText('Suggestion from @author on file:1-4')).not.toBeInTheDocument()
  })
})
