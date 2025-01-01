import {describe, expect, it, vi} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {screen, waitFor} from '@testing-library/react'
import {createRef} from 'react'

import {render} from '../../test-utils/helpers'
import {InlineEdit} from '../InlineEdit'

describe('InlineEdit', () => {
  it('only renders the children when not enabled', () => {
    const {container} = render(
      <InlineEdit enabled={false}>
        <p>CHILDREN</p>
      </InlineEdit>,
    )
    // This is fine, I want to perfom an assertion on the producing HTML.
    // eslint-disable-next-line testing-library/no-node-access
    const child = container.firstChild
    expect(child?.nodeName).toBe('P')
    expect(child?.textContent).toBe('CHILDREN')
  })

  it('renders an edit button when enabled', () => {
    render(<InlineEdit enabled>CHILDREN</InlineEdit>)
    expect(screen.getByText('CHILDREN')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Edit'})).toBeInTheDocument()
  })

  it('can edit a value', async () => {
    render(<InlineEdit enabled>CHILDREN</InlineEdit>)
    expect(screen.getByText('CHILDREN')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', {name: 'Edit'}))
    const input = screen.getByLabelText('Edit value', {selector: 'input'})

    await waitFor(() => expect(input).toHaveFocus())

    await userEvent.fill(input, 'new value')
    expect(input).toHaveValue('new value')
  })

  it('pressing Escape should cancel the edit', async () => {
    render(<InlineEdit enabled>CHILDREN</InlineEdit>)

    expect(screen.getByText('CHILDREN'), 'We should be in the default state').toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', {name: 'Edit'}))

    expect(screen.queryByText('CHILDREN'), 'The children should not render when editing').toBeNull()

    const input = screen.getByLabelText('Edit value', {selector: 'input'})
    await userEvent.fill(input, 'new value')
    await userEvent.type(input, '{Escape}')

    await waitFor(() => expect(input).not.toBeInTheDocument())

    expect(screen.getByText('CHILDREN'), 'We should be in the default state again').toBeInTheDocument()
  })

  it('pressing enter on a field should save it', async () => {
    const onSave = vi.fn()
    render(
      <InlineEdit enabled onSave={onSave}>
        CHILDREN
      </InlineEdit>,
    )
    await userEvent.click(screen.getByRole('button', {name: 'Edit'}))
    await userEvent.fill(screen.getByLabelText('Edit value', {selector: 'input'}), 'new value')
    await userEvent.keyboard('[Enter]')
    expect(onSave).toHaveBeenCalledExactlyOnceWith('new value')
  })

  it('pressing enter on the edit button should open show the input field', async () => {
    const onSave = vi.fn()
    render(
      <InlineEdit enabled onSave={onSave}>
        CHILDREN
      </InlineEdit>,
    )

    screen.getByRole('button', {name: 'Edit'}).focus()
    await userEvent.keyboard('[Enter]')

    const input = screen.getByLabelText('Edit value', {selector: 'input'})
    await userEvent.fill(input, 'new value')
    expect(input).toHaveValue('new value')
  })

  it('clicking the save button, should save', async () => {
    const onSave = vi.fn()
    render(
      <InlineEdit enabled onSave={onSave}>
        CHILDREN
      </InlineEdit>,
    )
    await userEvent.click(screen.getByRole('button', {name: 'Edit'}))
    await userEvent.fill(screen.getByLabelText('Edit value', {selector: 'input'}), 'new value')
    await userEvent.click(screen.getByRole('button', {name: 'Save edits'}))
    expect(onSave).toHaveBeenCalledExactlyOnceWith('new value')
  })

  it('clicking the cancel button, should reset', async () => {
    const onSave = vi.fn()
    render(
      <InlineEdit enabled onSave={onSave}>
        CHILDREN
      </InlineEdit>,
    )
    await userEvent.click(screen.getByRole('button', {name: 'Edit'}))
    await userEvent.fill(screen.getByLabelText('Edit value', {selector: 'input'}), 'new value')
    await userEvent.click(screen.getByRole('button', {name: 'Cancel edit'}))

    expect(onSave).not.toHaveBeenCalled()
    expect(screen.getByText('CHILDREN')).toBeInTheDocument()
  })

  it('uses the default value for the input when given', async () => {
    render(
      <InlineEdit enabled defaultValue="DEFAULT VALUE">
        CHILDREN
      </InlineEdit>,
    )
    await userEvent.click(screen.getByRole('button', {name: 'Edit'}))
    expect(screen.getByLabelText('Edit value', {selector: 'input'})).toHaveValue('DEFAULT VALUE')
  })

  it('returns focus on cancel', async () => {
    const ref = createRef<HTMLInputElement>()

    render(
      <>
        <input type="checkbox" ref={ref} />
        <InlineEdit enabled returnFocusRef={ref}>
          CHILDREN
        </InlineEdit>
        ,
      </>,
    )
    await userEvent.click(screen.getByRole('button', {name: 'Edit'}))
    const input = screen.getByLabelText('Edit value', {selector: 'input'})
    await waitFor(() => expect(input).toHaveFocus())
    await userEvent.type(input, '{Escape}')
    await waitFor(() => expect(ref.current!).toHaveFocus())
  })

  it('can describe buttons', async () => {
    render(
      <>
        <span id="my-id">test-case</span>
        <InlineEdit enabled aria-describedby="my-id">
          CHILDREN
        </InlineEdit>
      </>,
    )
    const el = await screen.findByRole('button', {name: 'Edit', description: 'test-case'})
    expect(el).toBeInTheDocument()
  })
})
