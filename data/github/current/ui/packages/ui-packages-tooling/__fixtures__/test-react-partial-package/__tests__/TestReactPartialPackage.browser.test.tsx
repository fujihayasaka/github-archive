import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {TestReactPartialPackage} from '../TestReactPartialPackage'
import {getTestReactPartialPackageProps} from './utils/mock-data'

it('Renders the TestReactPartialPackage', () => {
  const props = getTestReactPartialPackageProps()
  render(<TestReactPartialPackage {...props} />)
  expect(screen.getByRole('article')).toHaveTextContent(props.exampleMessage)
})
