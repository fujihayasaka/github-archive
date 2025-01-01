import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {TestReactComponentPackage} from '../TestReactComponentPackage'

it('Renders the TestReactComponentPackage', () => {
  const message = 'Hello React!'
  render(<TestReactComponentPackage exampleMessage={message} />)
  expect(screen.getByRole('article')).toHaveTextContent(message)
})
