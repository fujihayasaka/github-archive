import type React from 'react'
import {Dialog} from '@primer/react/experimental'
import {ActionMenu, ActionList} from '@primer/react'
import {
  type OrganizationSecurityConfiguration,
  DialogType,
  type ConfigurationConfirmationSummary,
  type ConfigurationPolicy,
  type PendingConfigurationChanges,
  type DialogProps,
} from '../../security-products-enablement-types'
import {
  applyConfiguration,
  confirmationSummary,
  createDialogFooterButtons,
  dialogSize,
  showDefaultForNewReposDropDown,
} from '../../utils/dialog-helpers'
import {DialogContext} from '../../contexts/DialogContext'
import {settingsEnterpriseSecurityProductsPath, settingsOrgSecurityProductsPath} from '@github-ui/paths'
import {useState, useMemo, useCallback} from 'react'
import {useNavigate, useSearchParams} from 'react-router-dom'
import {useAppContext} from '../../contexts/AppContext'
import ConfirmationDialog from '../ConfirmationDialog'

interface ApplyToButtonProps {
  configuration: OrganizationSecurityConfiguration
}

const ApplyToButton: React.FC<ApplyToButtonProps> = ({configuration}) => {
  const navigate = useNavigate()
  const {
    organization,
    enterprise,
    capabilities,
    docsUrls,
    githubRecommendedConfiguration,
    customSecurityConfigurations,
    customEnterpriseSecurityConfigurations,
    renderContext,
  } = useAppContext()
  const [searchParams] = useSearchParams()
  const [pendingConfigurationChanges, setPendingConfigurationChanges] = useState({} as PendingConfigurationChanges)
  const [confirmationDialogSummary, setConfirmationDialogSummary] = useState<ConfigurationConfirmationSummary | null>(
    null,
  )

  const owner = renderContext === 'enterprise' ? enterprise!.slug : organization

  const [dialogType, setDialogType] = useState<DialogType | null>(null)
  const [configurationPolicy, setConfigurationPolicy] = useState<ConfigurationPolicy>({
    defaultForNewPublicRepos: false,
    defaultForNewPrivateRepos: false,
  })

  const dialogContextValue = useMemo(
    () => ({configurationPolicy, setConfigurationPolicy, dialogType, setDialogType}),
    [configurationPolicy, setConfigurationPolicy, dialogType, setDialogType],
  )

  const onCloseDialog = useCallback(() => {
    setDialogType(null)
    setConfirmationDialogSummary(null)
    setConfigurationPolicy({defaultForNewPublicRepos: false, defaultForNewPrivateRepos: false})
  }, [])

  const customConfigs = [...(customSecurityConfigurations || []), ...(customEnterpriseSecurityConfigurations || [])]

  const shouldSetNewRepoDefaults = showDefaultForNewReposDropDown(customConfigs, githubRecommendedConfiguration)

  const confirmConfigApplication = useCallback(
    async (config: OrganizationSecurityConfiguration, overrideExistingConfig?: boolean, applyToAll?: boolean) => {
      setPendingConfigurationChanges({config, overrideExistingConfig, applyToAll})
      setDialogType(DialogType.APPLY)

      await confirmationSummary(
        setConfirmationDialogSummary,
        owner,
        renderContext,
        config.id,
        overrideExistingConfig,
        applyToAll,
        [],
        '',
        config.enable_ghas,
      )
    },
    [renderContext, owner],
  )

  const applyPendingConfigurationChanges = useCallback(async () => {
    const returnTo =
      renderContext === 'enterprise'
        ? settingsEnterpriseSecurityProductsPath({enterprise: owner})
        : settingsOrgSecurityProductsPath({org: owner, tip: searchParams.get('tip')})

    const source = renderContext === 'enterprise' ? 'enterprise_config_table' : 'config_table'

    const result = await applyConfiguration(
      pendingConfigurationChanges,
      renderContext,
      owner,
      navigate,
      source,
      [],
      shouldSetNewRepoDefaults,
      dialogContextValue,
      returnTo,
    )

    if (result && result.status === 422) setDialogType(DialogType.UPDATE_FAILED)
  }, [
    renderContext,
    pendingConfigurationChanges,
    owner,
    navigate,
    shouldSetNewRepoDefaults,
    dialogContextValue,
    searchParams,
  ])

  const dialogMessages = () => {
    switch (dialogType) {
      case 'updateFailed':
        return 'Another enablement event is in progress. Please try again later.'
      case 'apply':
        return (
          <DialogContext.Provider value={dialogContextValue}>
            <ConfirmationDialog
              confirmationDialogSummary={confirmationDialogSummary}
              pendingConfigurationChanges={pendingConfigurationChanges}
              showDefaultForNewReposDropDown={shouldSetNewRepoDefaults}
              hasPublicRepos={capabilities.hasPublicRepos}
              ghasPurchased={capabilities.ghasPurchased}
              docsBillingUrl={docsUrls.ghasBilling}
            />
          </DialogContext.Provider>
        )
      default:
        return ''
    }
  }

  const dialogProps: Partial<Record<DialogType, DialogProps>> = {
    updateFailed: {
      'data-testid': 'update-failed-dialog',
      title: 'Unable to apply configuration',
      footerButtons: createDialogFooterButtons({
        confirmOnClick: () => setDialogType(null),
        confirmContent: 'Okay',
        confirmButtonType: 'default',
      }),
    },
    apply: {
      'data-testid': 'apply-configuration-dialog',
      title: 'Apply configuration?',
      footerButtons: createDialogFooterButtons({
        cancelOnClick: () => onCloseDialog(),
        confirmOnClick: () => {
          applyPendingConfigurationChanges()
          onCloseDialog()
        },
        confirmContent: 'Apply',
      }),
    },
  }

  return (
    <>
      {dialogType && dialogProps[dialogType] && (
        <Dialog {...dialogProps[dialogType]} onClose={() => setDialogType(null)} sx={dialogSize}>
          {dialogMessages()}
        </Dialog>
      )}
      <ActionMenu>
        <ActionMenu.Button data-testid={`configuration-${configuration.id}-button`}>Apply to</ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList>
            <ActionList.Item onSelect={() => confirmConfigApplication(configuration, true, true)}>
              All repositories
            </ActionList.Item>
            <ActionList.Item onSelect={() => confirmConfigApplication(configuration, false, true)}>
              All repositories without configurations
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
}

export default ApplyToButton
