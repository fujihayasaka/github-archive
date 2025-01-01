import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getRoleFgpsDialogProps} from '../../test-utils/mock-data'
import {RoleFgpsDialog} from '../../components/RoleFgpsDialog'
import {FgpScopes} from '../../types/FgpMetadata'

test('Renders dialog', () => {
  const props = getRoleFgpsDialogProps()
  render(<RoleFgpsDialog {...props} />)

  const fgps = Object.values(FgpScopes).map(scope => props.fgpMetadata[scope])

  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  const title = screen.getByRole('heading', {name: props.title})
  expect(title).toBeInTheDocument()
  const subtitle = screen.getByRole('heading', {name: props.subtitle!})
  expect(subtitle).toBeInTheDocument()

  for (const [index, scope] of Object.values(FgpScopes).entries()) {
    if (Object.keys(fgps[index]!).length === 0) {
      // empty scopes are not rendered
      continue
    }

    const scopeText = screen.getByText(scope)
    expect(scopeText).toBeInTheDocument()
    const scopedFgps = fgps[index]!
    const categoryName = Object.keys(scopedFgps)[0]!
    const category = screen.getByText(categoryName)
    expect(category).toBeInTheDocument()
    const permission = screen.getByText(scopedFgps[categoryName]![0]!)
    expect(permission).toBeInTheDocument()
  }
})

test('Renders dialog with empty permissions notice', () => {
  const props = getRoleFgpsDialogProps({Enterprise: {}, Organization: {}, Repository: {}})
  render(<RoleFgpsDialog {...props} />)

  const emptyMessage = screen.getByText('No permissions have been added to this role.')
  expect(emptyMessage).toBeInTheDocument()

  for (const scope of Object.keys(props.fgpMetadata)) {
    const scopeText = screen.queryByText(scope)
    expect(scopeText).not.toBeInTheDocument()
  }
})

test('Closing dialog calls onClose callback - click', async () => {
  const props = getRoleFgpsDialogProps()
  const {user} = render(<RoleFgpsDialog {...props} />)

  const closeButtons = await screen.findAllByRole('button')
  expect(closeButtons.length).toBe(2)

  await user.click(closeButtons[0]!)
  await user.click(closeButtons[1]!)
  expect(props.onClose).toHaveBeenCalledTimes(2)
})
