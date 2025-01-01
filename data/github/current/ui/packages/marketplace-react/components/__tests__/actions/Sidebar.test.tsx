import {Sidebar} from '../../actions/Sidebar'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockRepository, mockReleaseData} from '../../../test-utils/mock-data'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'

describe('Sidebar', () => {
  test('Renders the About section', () => {
    render(
      <Sidebar
        action={mockActionListing({description: 'test'})}
        repository={mockRepository()}
        releaseData={mockReleaseData()}
        repoAdminableByViewer
      />,
    )

    expect(screen.getByTestId('about')).toBeInTheDocument()
  })

  test('Renders the VerifiedOwner section', () => {
    render(
      <Sidebar
        action={mockActionListing({isVerifiedOwner: true})}
        repository={mockRepository()}
        releaseData={mockReleaseData()}
        repoAdminableByViewer
      />,
    )

    expect(screen.getByTestId('verified-owner')).toBeInTheDocument()
  })

  test('Renders the Tags section', () => {
    render(
      <Sidebar
        action={mockActionListing({categories: [{name: 'Category 1', slug: 'category-1'}]})}
        repository={mockRepository()}
        releaseData={mockReleaseData()}
        repoAdminableByViewer
      />,
    )

    expect(screen.getByTestId('tags')).toBeInTheDocument()
  })

  test('Renders the Contributors section', () => {
    render(
      <Sidebar
        action={mockActionListing()}
        repository={mockRepository({contributorsCount: 10})}
        releaseData={mockReleaseData()}
        repoAdminableByViewer
      />,
    )

    expect(screen.getByTestId('contributors')).toBeInTheDocument()
  })

  test('Renders the Resources section', () => {
    render(
      <Sidebar
        action={mockActionListing()}
        repository={mockRepository()}
        releaseData={mockReleaseData()}
        repoAdminableByViewer
      />,
    )

    expect(screen.getByTestId('resources')).toBeInTheDocument()
  })

  test('Renders the ThirdPartyStatement section', () => {
    render(
      <Sidebar
        action={mockActionListing()}
        repository={mockRepository({isThirdParty: true})}
        releaseData={mockReleaseData()}
        repoAdminableByViewer
      />,
    )

    expect(screen.getByTestId('third-party-statement')).toBeInTheDocument()
  })
})
