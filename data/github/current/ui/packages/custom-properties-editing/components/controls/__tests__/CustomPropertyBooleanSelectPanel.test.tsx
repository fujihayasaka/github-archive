import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {ComponentProps} from 'react'

import {CustomPropertyBooleanSelectPanel} from '../CustomPropertyBooleanSelectPanel'

const onChangeMock = jest.fn()
const sampleProps: ComponentProps<typeof CustomPropertyBooleanSelectPanel> = {
  mixed: false,
  onChange: onChangeMock,
  propertyValue: 'true',
  propertyName: 'legacy',
  defaultValue: null,
}

beforeEach(() => onChangeMock.mockClear())

describe('CustomPropertyBooleanSelectPanel', () => {
  it('drops down all options and changes selected on click', async () => {
    const {user} = render(<CustomPropertyBooleanSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.queryAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: 'false'}))
    expect(onChangeMock).toHaveBeenCalledWith('false')
    // Popup is closed on click
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })

  it('filter options and selects it on click, empty option is always displayed', async () => {
    const {user} = render(<CustomPropertyBooleanSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    const filterBox = screen.getByRole('textbox')

    await user.click(filterBox)
    await user.paste('false')

    expect(screen.queryAllByRole('option')).toHaveLength(2)

    expect(screen.getByRole('option', {name: '(Empty)'})).toBeInTheDocument()

    await user.click(screen.getByRole('option', {name: 'false'}))
    expect(onChangeMock).toHaveBeenCalledWith('false')
  })

  it('show no matches if filter cannot find anything', async () => {
    const {user} = render(<CustomPropertyBooleanSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    const filterBox = screen.getByRole('textbox')
    await user.click(filterBox)
    await user.paste('not-here')
    expect(screen.getByRole('option', {name: 'No matches'})).toBeInTheDocument()
  })

  it('can use empty option to unset value', async () => {
    const {user} = render(<CustomPropertyBooleanSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.getAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: '(Empty)'}))
    expect(onChangeMock).toHaveBeenCalledWith('')
    // Popup is closed on click
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })

  it('clicking already selected option closes panel', async () => {
    const {user} = render(<CustomPropertyBooleanSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.getAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: 'true'}))
    expect(onChangeMock).not.toHaveBeenCalled()
    // Popup is closed on click
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })

  it('can select default option in the panel', async () => {
    const {user} = render(<CustomPropertyBooleanSelectPanel {...sampleProps} defaultValue="false" />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.getAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: /^Default \(/}))
    expect(onChangeMock).toHaveBeenCalledWith('')
    // Popup is closed on click
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })
})
