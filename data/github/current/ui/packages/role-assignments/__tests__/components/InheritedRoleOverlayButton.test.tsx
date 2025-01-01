import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {InheritedRoleOverlayButton} from '../../components/InheritedRoleOverlayButton'

test('Renders InheritedRoleOverlayButton and toggles overlay visibility', async () => {
  const {user} = render(<InheritedRoleOverlayButton />)

  const button = screen.getByRole('button', {name: 'This role cannot be removed'})
  expect(button).toBeInTheDocument()

  // Overlay should not be visible initially
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

  // Click the button to open the overlay
  await user.click(button)
  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  expect(dialog).toHaveTextContent('Inherited roles can only be removed by removing the member or role from the team.')
})
