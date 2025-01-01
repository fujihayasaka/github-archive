import {getServerLicensesFooterProps} from '../../test-utils/mock-data'
import {ServerLicensesFooter} from '../ServerLicensesFooter'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

const renderServerLicensesFooter = (overrideProps = {}) => {
  return render(<ServerLicensesFooter {...getServerLicensesFooterProps()} {...overrideProps} />)
}

describe('ServerLicensesFooter Component', () => {
  test('renders for the bundled sku', () => {
    renderServerLicensesFooter()

    const textEl = screen.queryByTestId('server-licenses-text')
    expect(textEl).toBeInTheDocument()

    expect(textEl).toHaveTextContent('Additional users from GitHub Connect: 5 for Advanced Security')
  })

  test('renders for the unbundled secret-protection sku', () => {
    renderServerLicensesFooter({
      licensesInfo: {
        prefix: 'Additional users from GitHub Connect: ',
        count: 5,
        suffix: ' for Secret Protection',
      },
    })

    const textEl = screen.queryByTestId('server-licenses-text')
    expect(textEl).toBeInTheDocument()

    expect(textEl).toHaveTextContent('Additional users from GitHub Connect: 5 for Secret Protection')
  })

  test('renders for the unbundled code-security sku', () => {
    renderServerLicensesFooter({
      licensesInfo: {
        prefix: 'Additional users from GitHub Connect: ',
        count: 5,
        suffix: ' for Code Security',
      },
    })

    const textEl = screen.queryByTestId('server-licenses-text')
    expect(textEl).toBeInTheDocument()

    expect(textEl).toHaveTextContent('Additional users from GitHub Connect: 5 for Code Security')
  })

  test('renders for both unbundled skus', () => {
    renderServerLicensesFooter({
      licensesInfo: {
        prefix: 'Additional users from GitHub Connect: ',
        parts: [
          {
            count: 3,
            suffix: ' for Secret Protection',
          },
          {
            count: 2,
            suffix: ' for Code Security',
          },
        ],
      },
    })

    const textEl = screen.queryByTestId('server-licenses-text')
    expect(textEl).toBeInTheDocument()

    expect(textEl).toHaveTextContent(
      'Additional users from GitHub Connect: 3 for Secret Protection, 2 for Code Security',
    )
  })
})
