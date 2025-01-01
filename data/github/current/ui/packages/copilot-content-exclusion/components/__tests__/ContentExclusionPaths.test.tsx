import {act, render, renderHook, screen} from '@testing-library/react'
import {useContentExclusionMutation, ContentExclusionPaths} from '../ContentExclusionPaths'
import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {getCodeMirrorInstance, deleteForward, typeInCodeMirror} from '@github-ui/code-mirror/test-helpers'

const userEvent = setupUserEvent()

const useCopilotContentExclusionMutation = jest.fn(({onComplete}) => {
  onComplete(
    {
      organization: 'test-org',
      lastEdited: {
        login: 'test-new-user',
        time: '2021-09-09T15:00:00Z',
        link: undefined,
      },
      message: 'successful message',
    },
    200,
  )
})

jest.mock('../../hooks/use-fetchers', () => ({
  useCopilotContentExclusionMutation() {
    return [useCopilotContentExclusionMutation, false]
  },
}))

function testRender(value = 'value') {
  return renderHook(() =>
    useContentExclusionMutation('ENDPOINT', {
      value,
      lastEdited: {
        login: 'LOGIN',
        time: String(new Date()),
        link: undefined,
      },
    }),
  )
}

test('renders default state', () => {
  const {result} = testRender()

  expect(result.current.canDiscard).toBe(false)
  expect(result.current.loading).toBe(false)
  expect(result.current.value).toBe('value')
  expect(result.current.fieldStatus).toBe(undefined)
})

test('resets field status on edit', () => {
  const {result} = testRender()

  expect(result.current.fieldStatus).toBe(undefined)
  act(() => result.current.onChange('new value'))
  act(() => result.current.onSave())
  expect(result.current.fieldStatus).toEqual({status: 'success', message: 'successful message'})
  act(() => result.current.onChange('new value 2'))
  expect(result.current.fieldStatus).toBe(undefined)
})

describe('save', () => {
  describe('contentExclusionSaveSpeedbumpFlag on', () => {
    test('opens dialog confirmation when deleting all values', async () => {
      render(
        <ContentExclusionPaths
          endpoint="ENDPOINT"
          initialValue="hi"
          initialLastEdited={{
            login: 'LOGIN',
            time: String(new Date()),
            link: undefined,
          }}
          label="Label"
          placeholder="Placeholder"
          contentExclusionSaveSpeedbumpFlag
        />,
      )
      await screen.findByTestId('codemirror-editor')

      const editor = getCodeMirrorInstance(screen)
      act(() => {
        deleteForward(editor)
        deleteForward(editor)
      })

      const saveButton = screen.getByRole('button', {name: 'Save changes'})
      await userEvent.click(saveButton)

      const dialog = screen.getByRole('dialog')
      expect(dialog).toBeVisible()
    })

    test('does not open dialog confirmation when saving new values', async () => {
      render(
        <ContentExclusionPaths
          endpoint="ENDPOINT"
          initialValue="hi"
          initialLastEdited={{
            login: 'LOGIN',
            time: String(new Date()),
            link: undefined,
          }}
          label="Label"
          placeholder="Placeholder"
          contentExclusionSaveSpeedbumpFlag
        />,
      )
      await screen.findByTestId('codemirror-editor')

      const editor = getCodeMirrorInstance(screen)
      act(() => {
        typeInCodeMirror(editor, 'hello ')
      })

      const saveButton = screen.getByRole('button', {name: 'Save changes'})
      await userEvent.click(saveButton)

      const dialog = screen.queryByRole('dialog')
      expect(dialog).not.toBeInTheDocument()
      expect(useCopilotContentExclusionMutation).toHaveBeenCalled()
    })
  })
  describe('contentExclusionSaveSpeedbumpFlag off', () => {
    test('does not open dialog confirmation when deleting all values', async () => {
      render(
        <ContentExclusionPaths
          endpoint="ENDPOINT"
          initialValue="hi"
          initialLastEdited={{
            login: 'LOGIN',
            time: String(new Date()),
            link: undefined,
          }}
          label="Label"
          placeholder="Placeholder"
          contentExclusionSaveSpeedbumpFlag={false}
        />,
      )
      await screen.findByTestId('codemirror-editor')

      const editor = getCodeMirrorInstance(screen)
      act(() => {
        deleteForward(editor)
        deleteForward(editor)
      })

      const saveButton = screen.getByRole('button', {name: 'Save changes'})
      await userEvent.click(saveButton)

      const dialog = screen.queryByRole('dialog')
      expect(dialog).not.toBeInTheDocument()

      expect(useCopilotContentExclusionMutation).toHaveBeenCalled()
    })
  })

  test('can save when input has new value', async () => {
    const {result} = testRender()

    expect(result.current.value).toBe('value')
    act(() => result.current.onChange('new value'))
    expect(result.current.value).toBe('new value')
    act(() => result.current.onSave())
  })
})

describe('discard', () => {
  it('can discard to original value', () => {
    const {result} = testRender()

    expect(result.current.value).toBe('value')
    act(() => result.current.onChange('new value'))
    expect(result.current.canDiscard).toBe(true)
    expect(result.current.value).toBe('new value')
    act(() => result.current.onDiscard())
    expect(result.current.canDiscard).toBe(false)
    expect(result.current.value).toBe('value')
  })

  it('resets to latest stable value', () => {
    const {result} = testRender()

    expect(result.current.value).toBe('value')
    act(() => result.current.onChange('new value'))
    expect(result.current.canDiscard).toBe(true)
    expect(result.current.value).toBe('new value')
    act(() => result.current.onSave())
    expect(result.current.canDiscard).toBe(false)
    expect(result.current.value).toBe('new value')
    act(() => result.current.onChange('new value 2'))
    expect(result.current.value).toBe('new value 2')
    expect(result.current.canDiscard).toBe(true)
    act(() => result.current.onDiscard())
    expect(result.current.value).toBe('new value')
  })

  test('can discard empty values', () => {
    const {result} = testRender()

    act(() => result.current.onChange(''))
    expect(result.current.value).toBe('')
    expect(result.current.canDiscard).toBe(true) // true because value changed from something to nothing
    act(() => result.current.onSave())
    expect(result.current.canDiscard).toBe(false)
    act(() => result.current.onChange('new value'))
    expect(result.current.canDiscard).toBe(true)
  })

  test('can discard to empty original', () => {
    const {result} = testRender('')

    expect(result.current.canDiscard).toBe(false)
    act(() => result.current.onChange('new value'))
    expect(result.current.value).toBe('new value')
    expect(result.current.canDiscard).toBe(true)
    act(() => result.current.onDiscard())
    expect(result.current.canDiscard).toBe(false)
    expect(result.current.value).toBe('')
  })
})
