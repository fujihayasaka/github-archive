import {getUsageHintProps} from '../../test-utils/mock-data'
import {screen} from '@testing-library/react'
import {ThemeProvider} from '@primer/react'
import {UsageHint} from '../UsageHint'
import {render} from '@github-ui/react-core/test-utils'

const renderLicenseUsageHint = (overrideProps = {}) => {
  return render(
    <ThemeProvider>
      <UsageHint {...getUsageHintProps()} {...overrideProps} />
    </ThemeProvider>,
  )
}

describe('UsageHint Component', () => {
  test('renders the hint UI elements', async () => {
    const {user} = renderLicenseUsageHint()

    const hintButton = screen.queryByTestId('usage-hint-button')
    expect(hintButton).toBeInTheDocument()

    // open the hint dialog
    await user.click(hintButton!)

    // Title
    const hintTitle = screen.queryByTestId('usage-hint-title')
    expect(hintTitle).toBeInTheDocument()
    expect(hintTitle).toHaveTextContent('Consumed licenses')

    // Description
    const hintDescription = screen.queryByTestId('usage-hint-description')
    expect(hintDescription).toBeInTheDocument()
    expect(hintDescription).toHaveTextContent(
      'Active committers who contributed to at least one private organization-owned or user-owned repository.',
    )

    // Learn more link
    const learnMoreLink = screen.queryByTestId('learn-more-link')
    expect(learnMoreLink).toBeInTheDocument()
    expect(learnMoreLink).toHaveAttribute('href', 'https://docs.github.com/en/billing')
  })
})
