import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ContentExclusionSettings} from '../ContentExclusionSettings'

const defaultProps = (props: Partial<React.ComponentProps<typeof ContentExclusionSettings>> = {}) => ({
  locationCopy: 'Location copy',
  applyCopy: 'Apply copy',
  orgLevelRules: [],
  entLevelRules: [],
  ...props,
})

describe('ContentExclusionSettings', () => {
  test('renders the content exclusion settings page', async () => {
    const props = defaultProps()
    render(<ContentExclusionSettings {...props} />)

    const expectedText = [
      'Copilot won’t be able to access or utilize the contents located in those specified paths.',
      'Location copy',
      'Apply copy',
    ]

    expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('Content exclusion')
    for (const text of expectedText) {
      expect(screen.getByText(text)).toBeInTheDocument()
    }
  })

  test('renders the content exclusion settings page for a repository with inherited rules', async () => {
    const props = defaultProps({
      orgLevelRules: [
        {
          paths: '/org1/*',
          link: '',
          name: 'org1',
        },
        {
          paths: '/org2/*',
          link: '',
          name: 'org2',
        },
      ],
      entLevelRules: [
        {
          paths: '/enterprise/*',
          link: '',
          name: 'enterprise1',
        },
      ],
    })
    render(<ContentExclusionSettings {...props} />)

    const expectedText = [
      'Copilot won’t be able to access or utilize the contents located in those specified paths.',
      'Location copy',
      'Apply copy',
      /Excluded paths inherited from organization org1/,
      /Excluded paths inherited from organization org2/,
      /Excluded paths inherited from enterprise enterprise1/,
      /Values defined by org1's administrators can't be edited/,
      /Values defined by org2's administrators can't be edited/,
      /Values defined by enterprise1's administrators can't be edited/,
      '/org1/*',
      '/org2/*',
      '/enterprise/*',
    ]

    expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('Content exclusion')
    for (const text of expectedText) {
      expect(screen.getByText(text)).toBeInTheDocument()
    }
  })

  test('renders the content exclusion settings page even when bad props are passed', async () => {
    const props = defaultProps({
      orgLevelRules: null,
      entLevelRules: undefined,
    })
    render(<ContentExclusionSettings {...(props as React.ComponentProps<typeof ContentExclusionSettings>)} />)

    const expectedText = [
      'Copilot won’t be able to access or utilize the contents located in those specified paths.',
      'Location copy',
      'Apply copy',
    ]

    expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('Content exclusion')
    for (const text of expectedText) {
      expect(screen.getByText(text)).toBeInTheDocument()
    }
  })
})
