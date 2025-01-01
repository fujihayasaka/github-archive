import '../../test-utils/mocks'

import {render, type User} from '@github-ui/react-core/test-utils'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {screen} from '@testing-library/react'

import {getWorkspaceEditorRoutePayload} from '../../test-utils/mock-data'
import {TestComponentWrapper} from '../../test-utils/TestComponentWrapper'
import type {FocusedTaskData, FocusedTaskSuggestion} from '../../utilities/workspace-editor-types'
import {
  buildSuggestionsStorageKey,
  buildSuggestionsStorageKeyV2,
  useLocalSuggestionState,
} from '../use-local-suggestion-state'

const readmeSuggestion = {filePath: 'README.md'} as FocusedTaskSuggestion
const indexjsSuggestion = {filePath: 'index.js'} as FocusedTaskSuggestion

const task = {
  sourceId: 1,
  suggestions: [readmeSuggestion, indexjsSuggestion],
} as unknown as FocusedTaskData

const otherTask = {
  sourceId: 2,
  suggestions: [],
} as unknown as FocusedTaskData

function TestComponent() {
  const {
    dismissSuggestion,
    getAppliedSuggestions,
    getDismissedSuggestions,
    isSingleSuggestionApplied,
    reopenSuggestion,
    resetSuggestionState,
    updateAppliedSuggestions,
  } = useLocalSuggestionState()

  // For compatibility testing we directly muck with storage some
  // Makes some of the setup clearer.
  const v1key = buildSuggestionsStorageKey('monalisa', 'smile', '1')
  const v2key = buildSuggestionsStorageKeyV2('monalisa', 'smile', '1')

  const [v1, setV1] = useLocalStorage<number[]>(v1key, [])
  const [v2, _setV2] = useLocalStorage<Record<string, unknown>>(v2key, {})

  return (
    <TestComponentWrapper>
      <input data-testid="force-v1-input" />
      <button
        onClick={() => {
          const input: HTMLInputElement = screen.getByTestId('force-v1-input')
          setV1(JSON.parse(input?.value))
        }}
      >
        Force V1
      </button>
      <div data-testid="raw-v1-storage">{JSON.stringify(v1)}</div>
      <div data-testid="raw-v2-storage">{JSON.stringify(v2)}</div>

      <div data-testid="is-readme-applied">{JSON.stringify(isSingleSuggestionApplied(task, readmeSuggestion))}</div>
      <div data-testid="is-indexjs-applied">{JSON.stringify(isSingleSuggestionApplied(task, indexjsSuggestion))}</div>

      <button onClick={() => updateAppliedSuggestions(task, task.suggestions)}>Apply</button>
      <button onClick={() => updateAppliedSuggestions(otherTask, otherTask.suggestions)}>Apply Other</button>
      <button onClick={() => updateAppliedSuggestions(task, [readmeSuggestion])}>Apply Single</button>
      <button onClick={() => resetSuggestionState()}>Reset</button>
      <div data-testid="applied-suggestions">{JSON.stringify(getAppliedSuggestions())}</div>

      <button onClick={() => dismissSuggestion(task)}>Dismiss</button>
      <button onClick={() => reopenSuggestion(task)}>Reopen</button>
      <div data-testid="dismissed-suggestions">{JSON.stringify(getDismissedSuggestions())}</div>
    </TestComponentWrapper>
  )
}

beforeEach(() => {
  window.localStorage.clear()
})

jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlag: jest.fn(),
}))

describe('Applied suggestions', () => {
  test('Empty to start', async () => {
    render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectAppliedSuggestionsToBe([])
  })

  test('Adds to suggestion list', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectAppliedSuggestionsToBe([])

    await click(user, 'Apply')
    await expectAppliedSuggestionsToBe([1])
  })

  test('Multiple adds are collapsed', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectAppliedSuggestionsToBe([])

    await click(user, 'Apply')
    await click(user, 'Apply')
    await expectAppliedSuggestionsToBe([1])
  })

  test('Reset suggestion list', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await click(user, 'Apply')
    await expectAppliedSuggestionsToBe([1])

    await click(user, 'Reset')
    await expectAppliedSuggestionsToBe([])
  })

  test('saves update to all suggestions', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await click(user, 'Apply')
    await expectAppliedSuggestionsToBe([1])
    await expectRawV2StorageToBe({'1': {files: ['README.md', 'index.js']}})
  })

  test('saves only single suggestion', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await click(user, 'Apply Single')
    await expectAppliedSuggestionsToBe([1])
    await expectRawV2StorageToBe({'1': {files: ['README.md']}})
  })

  test('remembers applied all diffs', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await click(user, 'Apply')
    await expectIsReadmeApplied(true)
    await expectIsIndexJsApplied(true)
  })

  test('remembers individual suggested diff', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await click(user, 'Apply Single')
    await expectIsReadmeApplied(true)
    await expectIsIndexJsApplied(false)
  })
})

// Some of this behavior may be required after v2 is around to stay.
// Evaluate the tests depending how much v1 support is retained.
describe('V1 -> V2 compatiblity', () => {
  test('V2 finds suggestions from V1 data if present', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await forceV1StorageTo(user, '[1,2,3]')
    await expectAppliedSuggestionsToBe([1, 2, 3])
  })

  test('V2 combines all the data', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await forceV1StorageTo(user, '[2,3]')
    await click(user, 'Apply')
    await expectAppliedSuggestionsToBe([1, 2, 3])
  })

  test('V2 treats all files as applied', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await forceV1StorageTo(user, '[1]')
    await expectIsReadmeApplied(true)
    await expectIsIndexJsApplied(true)
  })

  test('V2 carries all files through saving', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await forceV1StorageTo(user, '[1]')
    await click(user, 'Apply Other')
    await expectIsReadmeApplied(true)
    await expectIsIndexJsApplied(true)
  })

  test('V2 writes back to V1', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectRawV1StorageToBe([])

    await click(user, 'Apply')
    await expectAppliedSuggestionsToBe([1])
    await expectRawV1StorageToBe([1])
  })

  test('V2 grabs V1 items it lacks', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await forceV1StorageTo(user, '[2]')
    await expectRawV1StorageToBe([2])

    await click(user, 'Apply')
    await expectAppliedSuggestionsToBe([1, 2])
    await expectRawV1StorageToBe([2, 1])
    await expectRawV2StorageToBe({
      '1': {files: ['README.md', 'index.js']},
      '2': {fully_applied: true, files: []},
    })
  })
})

describe('Dismissed suggestions', () => {
  test('Empty to start', async () => {
    render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectDismissedSuggestionsToBe([])
  })

  test('Adds to suggestion list', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectDismissedSuggestionsToBe([])

    await click(user, 'Dismiss')
    await expectDismissedSuggestionsToBe([1])
  })

  test('Multiple dismissals are fine', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectDismissedSuggestionsToBe([])

    await click(user, 'Dismiss')
    await click(user, 'Dismiss')
    await expectDismissedSuggestionsToBe([1])
  })

  test('Reopen dismissed', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectDismissedSuggestionsToBe([])

    await click(user, 'Dismiss')
    await expectDismissedSuggestionsToBe([1])

    await click(user, 'Reopen')
    await expectDismissedSuggestionsToBe([])
  })

  test('Reopen when not dismissed is fine', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await expectDismissedSuggestionsToBe([])

    await click(user, 'Reopen')
    await expectDismissedSuggestionsToBe([])
  })

  test('Reset dismissal list', async () => {
    const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload({path: 'readme'})})

    await click(user, 'Dismiss')
    await expectDismissedSuggestionsToBe([1])

    await click(user, 'Reset')
    await expectDismissedSuggestionsToBe([])
  })
})

async function expectAppliedSuggestionsToBe(expected: unknown) {
  await expectData('applied-suggestions', expected)
}

async function expectDismissedSuggestionsToBe(expected: unknown) {
  await expectData('dismissed-suggestions', expected)
}

async function expectRawV1StorageToBe(expected: unknown) {
  await expectData('raw-v1-storage', expected)
}

async function expectRawV2StorageToBe(expected: unknown) {
  await expectData('raw-v2-storage', expected)
}

async function expectIsReadmeApplied(expected: boolean) {
  await expectData('is-readme-applied', expected)
}

async function expectIsIndexJsApplied(expected: boolean) {
  await expectData('is-indexjs-applied', expected)
}

async function expectData(id: string, expected: unknown) {
  const data = await screen.findByTestId(id)
  expect(JSON.parse(data.innerHTML)).toEqual(expected)
}

async function forceV1StorageTo(user: User, data: string) {
  const input: HTMLInputElement = await screen.findByTestId('force-v1-input')
  input.value = data
  await click(user, 'Force V1')
}

async function click(user: User, buttonText: string) {
  const button = screen.getByText(buttonText)
  await user.click(button)
}
