import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import type {ComponentProps} from 'react'

import {VariantProvider} from '../../ListView/VariantContext'
import {ListItemDescription} from '../Description'

function renderDescription(props: ComponentProps<typeof ListItemDescription>) {
  return render(
    <VariantProvider variant="default">
      <ListItemDescription {...props} />
    </VariantProvider>,
  )
}

it('renders with children', () => {
  renderDescription({children: <a href="/my-url">foo</a>})

  const description = screen.getByTestId('list-view-item-description')
  expect(within(description).getByRole('link', {name: 'foo'})).toHaveAttribute('href', '/my-url')
})

it('renders custom styling', () => {
  renderDescription({style: {fontWeight: 'bold'}})

  const description = screen.getByTestId('list-view-item-description')
  expect(description).toHaveStyle('font-weight: bold') // custom styling
})
