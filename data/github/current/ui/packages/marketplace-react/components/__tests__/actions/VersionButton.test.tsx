import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {mockRepository, mockReleaseData, mockRelease} from '../../../test-utils/mock-data'
import {VersionButton} from '../../actions/VersionButton'
import {render} from '@github-ui/react-core/test-utils'
import {screen, act} from '@testing-library/react'

describe('VersionButton', () => {
  const props = {
    releaseData: mockReleaseData(),
    action: mockActionListing(),
    repository: mockRepository(),
  }

  describe('When there is a selected release', () => {
    it('Renders code snippet button for selected release', () => {
      render(
        <VersionButton
          {...props}
          releaseData={mockReleaseData({selectedRelease: mockRelease({tagName: 'selected version'})})}
        />,
      )

      expect(screen.getByRole('button', {name: 'Use selected version'})).toBeInTheDocument()
    })
  })

  describe('When there is no selected release', () => {
    it('Renders code snippet button for latest release', () => {
      render(<VersionButton {...props} releaseData={mockReleaseData({selectedRelease: undefined})} />)

      expect(screen.getByRole('button', {name: 'Use latest version'})).toBeInTheDocument()
    })
  })

  describe('When the code snippet button is clicked', () => {
    it('Opens the code snippet dialog', () => {
      render(<VersionButton {...props} />)

      expect(screen.queryByTestId('code-snippet-dialog')).not.toBeInTheDocument()

      const button = screen.getByRole('button', {name: /Use/i})
      act(() => button.click())

      expect(screen.getByTestId('code-snippet-dialog')).toBeInTheDocument()
    })
  })

  it('Renders the version picker button', () => {
    render(<VersionButton {...props} />)

    expect(screen.getByRole('button', {name: 'Choose a version'})).toBeInTheDocument()
  })

  describe('When the version picker button is clicked', () => {
    it('Opens the version picker dialog', () => {
      render(<VersionButton {...props} />)

      expect(screen.queryByTestId('version-picker-dialog')).not.toBeInTheDocument()

      const button = screen.getByRole('button', {name: 'Choose a version'})
      act(() => button.click())

      expect(screen.getByTestId('version-picker-dialog')).toBeInTheDocument()
    })
  })
})
