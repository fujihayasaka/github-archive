import {act, render, screen} from '@testing-library/react'
import {createRef} from 'react'
import type {IssueFormElementRef} from '../../types'
import {TextAreaElementInternal, type SharedTextAreaProps, type TextAreaElementInternalProps} from '../TextAreaElement'
import safeStorage from '@github-ui/safe-storage'
import {setupUserEvent} from '@github-ui/react-core/test-utils'

const userEvent = setupUserEvent()

test("ref.focus() triggers the CommentBox's focus", () => {
  const {formControlRef} = renderElement()

  // TODO: We should fetch by label
  // Affects https://github.com/github/accessibility-audits/issues/5297
  expect(screen.getByRole('textbox')).not.toHaveFocus()

  act(() => {
    formControlRef.current?.focus()
  })

  expect(screen.getByRole('textbox')).toHaveFocus()
})

test("ref.focus() triggers the textarea's focus", () => {
  const {formControlRef} = renderElement({
    render: 'yes please thank you',
  })

  expect(screen.getByLabelText('cool text box')).not.toHaveFocus()

  formControlRef.current?.focus()

  expect(screen.getByLabelText('cool text box')).toHaveFocus()
})

test('respects the session storage item', () => {
  const sessionStorageKey = 'test-input'
  const storageValue = 'test value'
  const safeSessionStorage = safeStorage('sessionStorage')
  safeSessionStorage.setItem(sessionStorageKey, JSON.stringify(storageValue))

  renderElement({sessionStorageKey})

  expect(screen.getByPlaceholderText('placeholder')).toHaveValue(storageValue)
})

test('renders codeblocks', async () => {
  const {formControlRef} = renderElement({
    render: 'SQL',
  })

  const inputElement = screen.getByPlaceholderText('placeholder')
  await userEvent.type(inputElement, 'select * from issues')
  expect(formControlRef.current?.markdown()).toBe('### cool text box\n\n```SQL\nselect * from issues\n```')
})

test('preserving existing text', async () => {
  const {formControlRef} = renderElement({
    label: 'label2',
    placeholder: 'placeholder2',
  })
  const inputElement = screen.getByPlaceholderText('placeholder2')
  await userEvent.type(inputElement, 'fluffity fluff')
  expect(formControlRef.current?.markdown()).toBe('### label2\n\nfluffity fluff')
})

const generateRandomKey = () => `test-key-${Math.random().toString()}`

function renderElement(overrides: Partial<TextAreaElementInternalProps & SharedTextAreaProps> = {}) {
  const formControlRef = createRef<IssueFormElementRef>()

  const {unmount, rerender} = render(
    <TextAreaElementInternal
      ref={formControlRef}
      label="cool text box"
      type="textarea"
      sessionStorageKey={generateRandomKey()}
      placeholder="placeholder"
      subject={{
        type: 'issue',
        repository: {
          databaseId: 0,
          nwo: 'owner/repo',
          slashCommandsEnabled: false,
        },
      }}
      {...overrides}
    />,
  )

  return {formControlRef, unmount, rerender}
}
