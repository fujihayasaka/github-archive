import {it, expect} from '@github-ui/tests'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {IndexPage} from '../Index'

it('Renders the index page', () => {
  render(<IndexPage />, {
    routePayload: 'payload',
  })
  expect(screen.getByRole('heading', {level: 1})).toHaveTextContent('React sandbox index page')
})
