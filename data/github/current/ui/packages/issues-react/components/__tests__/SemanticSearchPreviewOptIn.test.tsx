import {render} from '@github-ui/react-core/test-utils'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {screen} from '@testing-library/react'
import {SemanticSearchPreviewOptIn} from '../SemanticSearchPreviewOptIn'

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

describe('SemanticSearchPreviewOptIn', () => {
  test('does not render feature preview disabled', async () => {
    mockUseFeatureFlag.mockImplementation(_ => false)

    render(<SemanticSearchPreviewOptIn />)
    expect(screen.queryByTestId('issues-semantic-search-preview-opt-in')).not.toBeInTheDocument()
  })

  test('renders when feature preview enabled', async () => {
    mockUseFeatureFlag.mockImplementation(feature => feature === 'issues_semantic_search_preview_opt_in')

    render(<SemanticSearchPreviewOptIn />)
    expect(screen.getByTestId('issues-semantic-search-preview-opt-in')).toBeInTheDocument()
    expect(screen.getByText('Try the new semantic search')).toBeInTheDocument()
    expect(screen.getByText('Learn more')).toBeInTheDocument()
    expect(screen.queryByText('Opt out of the new semantic search')).not.toBeInTheDocument()
    expect(screen.queryByText('Give feedback')).not.toBeInTheDocument()
  })

  test('renders when user is opted in feature preview', async () => {
    mockUseFeatureFlag.mockImplementation(feature => feature === 'issues_semantic_search_preview_enabled')

    render(<SemanticSearchPreviewOptIn />)
    expect(screen.getByTestId('issues-semantic-search-preview-opt-in')).toBeInTheDocument()
    expect(screen.getByText('Opt out of the new semantic search')).toBeInTheDocument()
    expect(screen.getByText('Give feedback')).toBeInTheDocument()
    expect(screen.queryByText('Try the new semantic search')).not.toBeInTheDocument()
    expect(screen.queryByText('Learn more')).not.toBeInTheDocument()
  })
})
