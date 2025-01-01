import {Body} from '../../actions/Body'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {mockRepository} from '../../../test-utils/mock-data'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'

describe('Body', () => {
  describe('When there is readme html', () => {
    const props = {
      readmeHtml: 'Body' as SafeHTMLString,
      helpUrl: 'www.help.com',
      repository: mockRepository(),
      action: mockActionListing(),
    }

    test('Renders the readme html as a markdown box', () => {
      render(<Body {...props} />)

      expect(screen.getByTestId('markdown-body')).toBeInTheDocument()
      expect(screen.getByText('Body')).toBeInTheDocument()
    })

    test('Does not render a blankslate', () => {
      render(<Body {...props} />)

      expect(screen.queryByText('No description')).not.toBeInTheDocument()
    })
  })

  describe('When there is not readme html', () => {
    const props = {
      readmeHtml: '' as SafeHTMLString,
      helpUrl: 'www.help.com',
      repository: mockRepository(),
      action: mockActionListing(),
    }

    test('Does not render a markdown box', () => {
      render(<Body {...props} />)

      expect(screen.queryByTestId('markdown-body')).not.toBeInTheDocument()
    })

    test('Renders a blankslate', () => {
      render(<Body {...props} />)

      expect(screen.getByText('No description')).toBeInTheDocument()
    })
  })

  test('Renders the contributors', () => {
    const props = {
      readmeHtml: 'Body' as SafeHTMLString,
      helpUrl: 'www.help.com',
      repository: mockRepository({contributorsCount: 1}),
      action: mockActionListing(),
    }

    render(<Body {...props} />)

    expect(screen.getByTestId('contributors')).toBeInTheDocument()
  })

  test('Renders the resources', () => {
    const props = {
      readmeHtml: 'Body' as SafeHTMLString,
      helpUrl: 'www.help.com',
      repository: mockRepository(),
      action: mockActionListing(),
    }

    render(<Body {...props} />)

    expect(screen.getByTestId('resources')).toBeInTheDocument()
  })

  test('Renders the third party statement', () => {
    const props = {
      readmeHtml: 'Body' as SafeHTMLString,
      helpUrl: 'www.help.com',
      repository: mockRepository({isThirdParty: true}),
      action: mockActionListing(),
    }

    render(<Body {...props} />)

    expect(screen.getByTestId('third-party-statement')).toBeInTheDocument()
  })
})
