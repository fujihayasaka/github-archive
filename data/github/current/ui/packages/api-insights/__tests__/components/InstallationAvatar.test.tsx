import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {InstallationAvatar} from '../../components/InstallationAvatar'

test('InstallationAvatar renders an icon and background', async () => {
  render(<InstallationAvatar icon_url="#" variant="medium" icon_background_color="DAF7A6" />)

  const container = screen.getByTestId('installation-avatar')
  const img = screen.getByTestId('github-avatar')
  expect(container).toBeInTheDocument()
  expect(container).toHaveStyle('background: #DAF7A6')
  expect(container).toHaveClass('installationAvatar')
  expect(container).toHaveClass('installationAvatar--white')
  expect(img).toBeInTheDocument()
  expect(img).toHaveClass('installationAvatarImg')
})

test('InstallationAvatar renders a small variant', async () => {
  render(<InstallationAvatar icon_url="#" variant="small" icon_background_color="DAF7A6" />)

  const container = screen.getByTestId('installation-avatar')
  const img = screen.getByTestId('github-avatar')
  expect(container).toBeInTheDocument()
  expect(container).toHaveStyle('background: #DAF7A6')
  expect(container).toHaveClass('installationAvatarSmall')
  expect(container).toHaveClass('installationAvatar--white')
  expect(img).toBeInTheDocument()
  expect(img).toHaveClass('installationAvatarImg')
})

test('InstallationAvatar default color is white', async () => {
  render(<InstallationAvatar icon_url="#" />)

  const container = screen.getByTestId('installation-avatar')
  const img = screen.getByTestId('github-avatar')
  expect(container).toBeInTheDocument()
  expect(container).toHaveStyle('background: #FFFFFF')
  expect(container).toHaveClass('installationAvatar')
  expect(container).toHaveClass('installationAvatar--black')
  expect(img).toBeInTheDocument()
  expect(img).toHaveClass('installationAvatarImg')
})
