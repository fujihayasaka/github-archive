import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {HiddenUnicodeBanner} from '../HiddenUnicodeBanner'

test('Renders the HiddenUnicodeBanner', async () => {
  render(<HiddenUnicodeBanner isShown={false} toggleShowHiddenCharacters={() => {}} />)

  expect(screen.getByRole('button', {name: 'Show hidden characters'})).toBeInTheDocument()
})

test('Renders the HiddenUnicodeBanner when the characters are shown', async () => {
  render(<HiddenUnicodeBanner isShown toggleShowHiddenCharacters={() => {}} />)

  expect(screen.getByRole('button', {name: 'Hide revealed characters'})).toBeInTheDocument()
})
