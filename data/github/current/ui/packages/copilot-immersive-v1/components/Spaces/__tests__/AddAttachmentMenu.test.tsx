import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {AddAttachmentMenu} from '../AddAttachmentMenu'

describe('AddAttachmentMenu', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    jest.spyOn(copilotFeatureFlags, 'customCopilotsFileUploads', 'get').mockReturnValue(true)
  })

  it('should render upload from computer menu item', async () => {
    const {user} = render(
      <AddAttachmentMenu
        findFileWorkerPath="/test/path"
        onResourcesAdded={noop}
        owner="test-owner"
        resourcesToSave={[]}
      >
        <button>Add Attachment</button>
      </AddAttachmentMenu>,
    )

    // Click the main button to open the menu
    const addButton = await screen.findByText('Add Attachment')
    await user.click(addButton)

    // Check if the upload menu item is present
    expect(await screen.findByText('Upload from computer')).toBeInTheDocument()

    // Check if the file input exists and is hidden
    const fileInput = await screen.findByTestId('file-upload-input')
    expect(fileInput).toBeInTheDocument()
    expect(fileInput).not.toBeVisible()
  })

  it('should not render upload functionality when feature flag is disabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'customCopilotsFileUploads', 'get').mockReturnValue(false)

    const {user} = render(
      <AddAttachmentMenu
        findFileWorkerPath="/test/path"
        onResourcesAdded={noop}
        owner="test-owner"
        resourcesToSave={[]}
      >
        <button>Add Attachment</button>
      </AddAttachmentMenu>,
    )

    // Click the main button to open the menu
    const addButton = await screen.findByText('Add Attachment')
    await user.click(addButton)

    // Check that the upload menu item is not present
    expect(screen.queryByText('Upload from computer')).not.toBeInTheDocument()

    // Check that the file input is not present
    expect(screen.queryByTestId('file-upload-input')).not.toBeInTheDocument()
  })
})
