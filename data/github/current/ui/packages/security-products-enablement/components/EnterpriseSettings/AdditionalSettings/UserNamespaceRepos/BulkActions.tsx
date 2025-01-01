import {ControlGroup} from '@github-ui/control-group'
import {Button, Link as PrimerLink} from '@primer/react'
import {bulkToggleUserNamespaceEnablement} from '../../../../utils/api-helpers'
import {useAppContext} from '../../../../contexts/AppContext'
import {Dialog, type DialogButtonProps} from '@primer/react/experimental'
import {useState} from 'react'
import type {FlashParams} from '../../../../security-products-enablement-types'

export interface BulkActionsProps {
  setFlashMessage: (flash: FlashParams) => void
}

const BulkActions: React.FC<BulkActionsProps> = ({setFlashMessage}) => {
  const [dialogType, setDialogType] = useState<string | null>(null)

  const {enterprise, docsUrls} = useAppContext()
  const enterpriseSlug = enterprise!.slug
  const enterpriseName = enterprise!.name

  const confirmToggle = (action: string) => {
    setDialogType(action)
  }

  const closeDialog = () => {
    setDialogType(null)
  }

  const renderDialog = () => {
    if (dialogType === 'enable_all') {
      const footerButtons: DialogButtonProps[] = [
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: closeDialog,
        },
        {
          buttonType: 'primary',
          content: 'Enable all',
          onClick: () => {
            bulkToggle('enable_all')
          },
        },
      ]
      return (
        <Dialog title="Enable for all repositories?" onClose={closeDialog} footerButtons={footerButtons} width="large">
          <p>
            <strong>This will turn on GitHub Advanced Security for all user namespace repositories.</strong>
          </p>
          <p>
            GitHub Advanced Security features are billed per active committer in private and internal repositories. You
            can still disable GitHub Advanced Security at the repository level.
          </p>
          <p>
            <PrimerLink href={docsUrls.ghasBilling} target="_blank">
              Learn more about Advanced Security billing.
            </PrimerLink>
          </p>
        </Dialog>
      )
    } else if (dialogType === 'disable_all') {
      const footerButtons: DialogButtonProps[] = [
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: closeDialog,
        },
        {
          buttonType: 'danger',
          content: 'Disable all',
          onClick: () => {
            bulkToggle('disable_all')
          },
        },
      ]
      return (
        <Dialog title="Disable for all repositories?" onClose={closeDialog} footerButtons={footerButtons} width="large">
          <p>
            <strong>This will turn off GitHub Advanced Security for all user namespace repositories.</strong>
          </p>
          <p>You can still enable GitHub Advanced Security at the repository level.</p>
        </Dialog>
      )
    }
  }

  const bulkToggle = async (toggle: string) => {
    const params = {toggle}
    const response = await bulkToggleUserNamespaceEnablement(enterpriseSlug, params)

    // Render a banner with feedback depending on result:
    if (response && response.success === true) {
      const verb = toggle === 'enable_all' ? 'Enabling' : 'Disabling'
      setFlashMessage({
        message: `${verb} GitHub Advanced Security on all ${enterpriseName} user namespace repositories. It may take a few minutes to process.`,
        variant: 'success',
      })
    } else {
      setFlashMessage({
        message: 'An error occurred and the process could not be completed. Please try again.',
        variant: 'danger',
      })
    }

    // Hide confirmation dialog:
    setDialogType(null)
  }

  return (
    <ControlGroup.Item>
      <ControlGroup.Title>GitHub Advanced Security for user namespace repositories</ControlGroup.Title>
      <ControlGroup.Description>
        GitHub Advanced Security is billed per active committer in user namespace repositories.
      </ControlGroup.Description>
      <ControlGroup.Custom>
        <div className="d-flex">
          {renderDialog()}
          <Button
            onClick={() => {
              confirmToggle('disable_all')
            }}
            sx={{mr: 2}}
            variant="danger"
          >
            Disable all
          </Button>
          <Button
            onClick={() => {
              confirmToggle('enable_all')
            }}
          >
            Enable all
          </Button>
        </div>
      </ControlGroup.Custom>
    </ControlGroup.Item>
  )
}

export default BulkActions
