import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {ComponentProps} from 'react'

import {CustomPropertyMultiSelectPanel} from '../CustomPropertyMultiSelectPanel'

const onChangeMock = jest.fn()
const sampleProps: ComponentProps<typeof CustomPropertyMultiSelectPanel> = {
  mixed: false,
  onChange: onChangeMock,
  propertyValue: ['ios', 'web'],
  propertyName: 'platform',
  defaultValue: null,
  allowedValues: ['android', 'ios', 'web'],
}

beforeEach(() => onChangeMock.mockClear())

describe('CustomPropertyMultiSelectPanel', () => {
  it('drops down all options and adds one on click', async () => {
    const {user} = render(<CustomPropertyMultiSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    expect(screen.queryAllByRole('option')).toHaveLength(3)
    await user.click(screen.getByRole('option', {name: 'android'}))
    expect(onChangeMock).toHaveBeenCalledWith(['ios', 'web', 'android'])
  })

  it('filter options and adds it on click', async () => {
    const {user} = render(<CustomPropertyMultiSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)
    const filterBox = screen.getByRole('textbox')
    await user.click(filterBox)
    await user.paste('andr')
    expect(screen.queryAllByRole('option')).toHaveLength(1)
    await user.click(screen.getByRole('option'))
    expect(onChangeMock).toHaveBeenCalledWith(['ios', 'web', 'android'])
  })

  it('popup keeps open while clicking options', async () => {
    const {rerender, user} = render(<CustomPropertyMultiSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)

    await user.click(screen.getByRole('option', {name: 'web'}))
    expect(onChangeMock).toHaveBeenCalledWith(['ios'])

    // The external value gets updated and the component is re-rendered with the new value
    rerender(<CustomPropertyMultiSelectPanel {...sampleProps} propertyValue={['ios']} />)

    await user.click(screen.getByRole('option', {name: 'android'}))
    expect(onChangeMock).toHaveBeenCalledWith(['ios', 'android'])
  })

  it('hides empty option from the list', async () => {
    const {user} = render(<CustomPropertyMultiSelectPanel {...sampleProps} />)

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)

    expect(screen.queryAllByRole('option')).toHaveLength(3)
    expect(screen.queryAllByRole('option').map(e => e.textContent)).toEqual(sampleProps.allowedValues)
  })

  it('can select default option in the panel', async () => {
    const {user} = render(
      <CustomPropertyMultiSelectPanel {...sampleProps} defaultValue={['android', 'ios']} onChange={onChangeMock} />,
    )

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)

    await user.click(screen.getByRole('option', {name: /^Default \(/}))
    expect(onChangeMock).toHaveBeenCalledWith([])

    // Default + 2 options included in default
    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(3)

    await user.click(screen.getByRole('option', {name: /^Default \(/}))
    expect(onChangeMock).toHaveBeenCalledWith(['android', 'ios'])

    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(2)
  })

  it('unselecting default sets default value as manual when filter applied', async () => {
    const {user} = render(
      <CustomPropertyMultiSelectPanel
        {...sampleProps}
        propertyValue={[]}
        defaultValue={['android', 'ios']}
        onChange={onChangeMock}
      />,
    )

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)

    // Default + 2 options included in default
    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(3)

    const filterBox = screen.getByRole('textbox')
    await user.click(filterBox)
    await user.paste('andr')

    // Default + android. ios is filtered out
    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(2)

    await user.click(screen.getByRole('option', {name: /^Default \(/}))
    expect(onChangeMock).toHaveBeenCalledWith(['ios', 'android'])
  })

  it('toggling a value not in the default values list unchecks default', async () => {
    const {user} = render(
      <CustomPropertyMultiSelectPanel
        {...sampleProps}
        propertyValue={[]}
        defaultValue={['android', 'ios']}
        onChange={onChangeMock}
      />,
    )

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)

    await user.click(screen.getByRole('option', {name: 'web'}))
    expect(onChangeMock).toHaveBeenCalledWith(['android', 'ios', 'web'])
  })

  it('toggling one of the values from default unchecks default', async () => {
    const {user} = render(
      <CustomPropertyMultiSelectPanel
        {...sampleProps}
        propertyValue={[]}
        defaultValue={['android', 'ios']}
        onChange={onChangeMock}
      />,
    )

    const selectPanel = screen.getByRole('button')
    await user.click(selectPanel)

    await user.click(screen.getByRole('option', {name: 'android'}))
    expect(onChangeMock).toHaveBeenCalledWith(['ios'])
  })
})
