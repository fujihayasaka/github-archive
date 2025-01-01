import type {SafeHTMLString} from '@github-ui/safe-html'
import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockShowModelPayload} from './mocks'
import {License} from '../License'

describe('License', () => {
  test('renders', () => {
    const modelLicense = '<h2>My terms</h2><p>I am super serious!</p>' as SafeHTMLString
    const payload = mockShowModelPayload({modelLicense})

    const {container} = render(<License />, {routePayload: payload})

    const licenseContentEl = within(container).getByTestId('license-content')
    expect(licenseContentEl).toBeInTheDocument()
    expect(within(licenseContentEl).getByRole('heading', {name: 'My terms', level: 2})).toBeInTheDocument()
    expect(within(licenseContentEl).getByRole('paragraph')).toHaveTextContent('I am super serious!')
  })
})
