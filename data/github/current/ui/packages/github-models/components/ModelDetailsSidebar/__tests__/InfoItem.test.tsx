import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {InfoItem} from '../InfoItem'

describe('InfoItem', () => {
  test('renders', () => {
    const label = "You won't believe the coffee beverage I have today."
    const children = 'Grande oat milk iced shaken blonde espresso with 1 pump classic syrup'

    const {container} = render(
      <InfoItem label={label} isInline>
        {children}
      </InfoItem>,
    )

    expect(within(container).getByText(label)).toBeInTheDocument()
    expect(within(container).getByText(children)).toBeInTheDocument()
  })
})
