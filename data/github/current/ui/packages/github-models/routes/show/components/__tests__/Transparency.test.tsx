import type {SafeHTMLString} from '@github-ui/safe-html'
import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockShowModelPayload} from './mocks'
import {Transparency} from '../Transparency'

describe('Transparency', () => {
  test('renders', () => {
    const modelTransparencyContent =
      '<h3>Ethical considerations</h3><p>Contact us at <a href="/some/link">this address</a></p>' as SafeHTMLString
    const payload = mockShowModelPayload({modelTransparencyContent})

    const {container} = render(<Transparency />, {routePayload: payload})

    const transparencyContentEl = within(container).getByTestId('transparency-content')
    expect(transparencyContentEl).toBeInTheDocument()
    expect(
      within(transparencyContentEl).getByRole('heading', {name: 'Ethical considerations', level: 3}),
    ).toBeInTheDocument()
    expect(within(transparencyContentEl).getByRole('paragraph')).toHaveTextContent('Contact us at this address')
    expect(within(transparencyContentEl).getByRole('link', {name: 'this address'})).toHaveAttribute(
      'href',
      '/some/link',
    )
  })
})
