import type React from 'react'
import {Button} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {createDialogFooterButtons, dialogSize} from '../../utils/dialog-helpers'
import {
  type FlashParams,
  type MiniSecurityConfiguration,
  type SecurityConfiguration,
  DialogType,
  RenderContext,
} from '../../security-products-enablement-types'
import {
  settingsBusinessSecurityAnalysisConfigurationsUpdatePath,
  settingsBusinessSecurityAnalysisPath,
  settingsOrgSecurityConfigurationsUpdatePath,
  settingsOrgSecurityProductsPath,
  settingsUserSecurityConfigurationsUpdatePath,
  settingsUserSecurityProductsPath,
} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useNavigate} from 'react-router-dom'
import pluralize from 'pluralize'
import {useDialogContext} from '../../contexts/DialogContext'
import {scrollToTop} from '../../utils/helpers'
import {useCallback, useState} from 'react'
import {fetchRepoCount} from '../../utils/api-helpers'
import {useAppContext} from '../../contexts/AppContext'

interface DeleteButtonProps {
  securityConfiguration?: SecurityConfiguration
  clearState: () => void
  setFlashMessage: (flash: FlashParams) => void
}

const DeleteButton: React.FC<DeleteButtonProps> = ({securityConfiguration, clearState, setFlashMessage}) => {
  const navigate = useNavigate()
  const {dialogType, setDialogType} = useDialogContext()
  const {organization, enterprise, renderContext} = useAppContext()
  const renderingEnterprise = renderContext === RenderContext.Enterprise
  const owner = renderingEnterprise ? enterprise!.slug : organization
  const [repoCount, setRepoCount] = useState<number>(0)

  const handleButtonClick = useCallback(
    async (type: DialogType, config: MiniSecurityConfiguration) => {
      const count = await fetchRepoCount(owner, config.id, renderContext)
      setRepoCount(count)
      setDialogType(type)
    },
    [owner, renderContext, setDialogType],
  )

  const destroy = async () => {
    const path = () => {
      switch (renderContext) {
        case RenderContext.Enterprise:
          return settingsBusinessSecurityAnalysisConfigurationsUpdatePath({
            business: owner,
            id: securityConfiguration!.id,
          })
        case RenderContext.Organization:
          return settingsOrgSecurityConfigurationsUpdatePath({org: organization, id: securityConfiguration!.id})
        case RenderContext.User:
          return settingsUserSecurityConfigurationsUpdatePath({id: securityConfiguration!.id})
        default:
          return ''
      }
    }

    const result = await verifiedFetchJSON(path(), {method: 'DELETE'})

    if (result.ok) {
      const redirectPath = () => {
        switch (renderContext) {
          case RenderContext.Enterprise:
            return settingsBusinessSecurityAnalysisPath({business: owner})
          case RenderContext.Organization:
            return settingsOrgSecurityProductsPath({org: organization})
          case RenderContext.User:
            return settingsUserSecurityProductsPath()
          default:
            return ''
        }
      }
      const flash = {message: `${securityConfiguration?.name} configuration successfully deleted.`}
      navigate(redirectPath(), {state: {flash}})
      setDialogType(null)
      scrollToTop()
      window.addEventListener('beforeunload', clearState)
    } else if (result.status === 422) {
      setDialogType(DialogType.UPDATE_FAILED)
    } else {
      const json = await result.json()
      setFlashMessage({message: `Failed to delete configuration: ${json.error}`, variant: `danger`})
      setDialogType(null)
      scrollToTop()
    }
  }

  const deleteDialogDefaultString = (configuration: MiniSecurityConfiguration) => {
    if (configuration?.default_for_new_public_repos && configuration?.default_for_new_private_repos) {
      return ' and as the default for all newly created repositories'
    } else if (configuration?.default_for_new_public_repos) {
      return ' and as the default for newly created public repositories'
    } else if (configuration?.default_for_new_private_repos) {
      return ' and as the default for newly created private and internal repositories'
    } else {
      return ''
    }
  }

  const deleteDialog = () => {
    return (
      <Dialog
        data-testid="delete-dialog"
        title="Delete this configuration?"
        footerButtons={createDialogFooterButtons({
          cancelOnClick: () => setDialogType(null),
          confirmOnClick: () => destroy(),
          confirmContent: 'Delete configuration',
          confirmButtonType: 'danger',
        })}
        onClose={() => setDialogType(null)}
        sx={dialogSize}
      >
        Deleting {securityConfiguration?.name} configuration will remove it from{' '}
        {pluralize('repository', repoCount, true)}
        {deleteDialogDefaultString(securityConfiguration!)}. This will not change existing repository settings. This
        action is permanent and cannot be reversed.
      </Dialog>
    )
  }

  const updateFailedDialog = () => {
    return (
      <Dialog
        data-testid="update-failed-dialog"
        title={`Unable to update ${securityConfiguration?.name}`}
        footerButtons={createDialogFooterButtons({
          confirmOnClick: () => setDialogType(null),
          confirmContent: 'Okay',
          confirmButtonType: 'default',
        })}
        onClose={() => setDialogType(null)}
        sx={dialogSize}
      >
        Another enablement event is in progress. Please try again later.
      </Dialog>
    )
  }

  const renderDialog = () => {
    if (dialogType === 'delete') {
      return deleteDialog()
    } else if (dialogType === 'updateFailed') {
      return updateFailedDialog()
    }
  }

  return (
    <div>
      {renderDialog()}
      <Button variant="danger" onClick={() => handleButtonClick(DialogType.DELETE, securityConfiguration!)}>
        Delete configuration
      </Button>
    </div>
  )
}

export default DeleteButton
