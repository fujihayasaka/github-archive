import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {MissingCombinationPlaceholder} from '../MissingCombinationPlaceholder'

describe('MissingCombinationPlaceholder', () => {
  test('renders', () => {
    const {container} = render(<MissingCombinationPlaceholder />)

    const placeholderEl = within(container).getByTestId('missing-combination-placeholder')
    expect(placeholderEl).toBeInTheDocument()
    expect(
      within(placeholderEl).getByRole('heading', {
        level: 2,
        name: 'Documentation for this language and SDK combination is unavailable',
      }),
    ).toBeInTheDocument()
    expect(within(placeholderEl).getByText('Try a different combination')).toBeInTheDocument()
  })
})
