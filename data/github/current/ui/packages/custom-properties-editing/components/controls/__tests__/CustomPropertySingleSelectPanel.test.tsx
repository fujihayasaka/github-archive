import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {ComponentProps} from 'react'

import {CustomPropertySingleSelectPanel} from '../CustomPropertySingleSelectPanel'

const onChangeMock = jest.fn()
const sampleProps: ComponentProps<typeof CustomPropertySingleSelectPanel> = {
  mixed: false,
  onChange: onChangeMock,
  propertyValue: 'prod',
  propertyName: 'env',
  defaultValue: null,
  allowedValues: ['test', 'prod'],
}

beforeEach(() => onChangeMock.mockClear())

describe('CustomPropertySingleSelectPanel', () => {
  it('drops down all options and changes selected on click', async () => {
    const {user} = render(<CustomPropertySingleSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.queryAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: 'test'}))
    expect(onChangeMock).toHaveBeenCalledWith('test')
    // Popup is closed on click
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })

  it('filter options and selects it on click, empty option is always displayed', async () => {
    const {user} = render(<CustomPropertySingleSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    const filterBox = screen.getByRole('textbox')

    await user.click(filterBox)
    await user.paste('test')

    expect(screen.queryAllByRole('option')).toHaveLength(2)

    expect(screen.getByRole('option', {name: '(Empty)'})).toBeInTheDocument()

    await user.click(screen.getByRole('option', {name: 'test'}))
    expect(onChangeMock).toHaveBeenCalledWith('test')
  })

  it('show no matches if filter cannot find anything', async () => {
    const {user} = render(<CustomPropertySingleSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    const filterBox = screen.getByRole('textbox')
    await user.click(filterBox)
    await user.paste('not-here')
    expect(screen.getByRole('option', {name: 'No matches'})).toBeInTheDocument()
  })

  it('can use empty option to unset value', async () => {
    const {user} = render(<CustomPropertySingleSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.getAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: '(Empty)'}))
    expect(onChangeMock).toHaveBeenCalledWith('')
    // Popup is closed on click
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })

  it('clicking already selected option closes panel', async () => {
    const {user} = render(<CustomPropertySingleSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.getAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: 'prod'}))
    expect(onChangeMock).not.toHaveBeenCalled()
    // Popup is closed on click
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })

  it('can select default option in the panel', async () => {
    const {user} = render(<CustomPropertySingleSelectPanel {...sampleProps} defaultValue="test" />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.getAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: /^Default \(/}))
    expect(onChangeMock).toHaveBeenCalledWith('')
    // Popup is closed on click
    expect(screen.queryAllByRole('option')).toHaveLength(0)
  })
})
