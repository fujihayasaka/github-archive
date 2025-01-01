import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {TestSsrReactPartialPackage} from '../TestSsrReactPartialPackage'
import {getTestSsrReactPartialPackageProps} from './utils/mock-data'

it('Renders the TestSsrReactPartialPackage', () => {
  const props = getTestSsrReactPartialPackageProps()
  render(<TestSsrReactPartialPackage {...props} />)
  expect(screen.getByRole('article')).toHaveTextContent(props.exampleMessage)
})
