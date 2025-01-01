import type React from 'react'
import {useState, useMemo} from 'react'
import pluralize from 'pluralize'
import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {settingsOrgSecurityProductsRepositoriesDeletePath} from '@github-ui/paths'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Box, Text, ActionList, ActionMenu, Button, Spinner, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {Blankslate, Dialog} from '@primer/react/experimental'
import {AlertIcon, RepoIcon} from '@primer/octicons-react'
import {useAppContext} from '../contexts/AppContext'
import {useRepositoryContext} from '../contexts/RepositoryContext'
import {useSelectedRepositoryContext} from '../contexts/SelectedRepositoryContext'
import {applyConfiguration, createDialogFooterButtons, confirmationSummary, dialogSize} from '../utils/dialog-helpers'
import {testIdProps} from '@github-ui/test-id-props'
import ConfirmationDialog from './ConfirmationDialog'
import RepositoryRow from './RepositoryRow'
import type {Action} from '@github-ui/action-bar'
import type {
  OrganizationSecurityConfiguration,
  ConfigurationConfirmationSummary,
  PendingConfigurationChanges,
  ChangesInProgress,
  DialogProps,
} from '../security-products-enablement-types'

interface RepositoryTableProps {
  setChangesInProgress: React.Dispatch<React.SetStateAction<ChangesInProgress>>
  configs: OrganizationSecurityConfiguration[]
  filterQuery: string
  flashBannerType: string | null
  pageCount: number
  totalRepositoryCount: number
  isQueryLoading: boolean
}

type DialogType = 'confirmation' | 'noConfig' | 'updateFailure'

// This is a work around to style the link for selecting and clearing all.
// This needs to be an inline style because there is a React class that overrides the GitHub `.btn-link` class.
// Once Primer addresses the "Select all" we can make this cleaner.
const selectAllStyle = {
  display: 'inline-block',
  padding: '0',
  fontSize: 'inherit',
  color: 'var(--fgColor-accent, var(--color-accent-fg))',
  textDecoration: 'none',
  cursor: 'pointer',
  backgroundColor: 'transparent',
  border: 'none',
  boxShadow: 'none',
}

const RepositoryTable: React.FC<RepositoryTableProps> = ({
  setChangesInProgress,
  configs,
  filterQuery,
  flashBannerType,
  pageCount,
  totalRepositoryCount,
  isQueryLoading,
}) => {
  const navigate = useNavigate()
  const {organization, renderContext, capabilities, docsUrls} = useAppContext()
  const {repositories} = useRepositoryContext()
  const orgHasRepos = totalRepositoryCount > 0
  const {selectedReposMap, setSelectedRepos, selectedReposCount, setSelectedReposCount} = useSelectedRepositoryContext()
  const selectedRepoIds = Object.keys(selectedReposMap).map(Number)
  const [confirmationDialogSummary, setConfirmationDialogSummary] = useState<ConfigurationConfirmationSummary | null>(
    null,
  )
  const [pendingConfigurationChanges, setPendingConfigurationChanges] = useState({} as PendingConfigurationChanges)
  const [dialogType, setDialogType] = useState<DialogType | null>(null)

  const spinnerAction = useMemo(
    () => ({
      key: 'spinner',
      render: () => <Spinner size="small" data-testid="spinner" />,
    }),
    [],
  )

  const toggleAllReposSelection = (selectAll: boolean, repoCount: number) => {
    setSelectedReposCount(selectAll ? repoCount : 0)
    setSelectedRepos(selectAll ? repositories.reduce((acc, repo) => ({...acc, [repo.id]: repo}), {}) : {})
  }

  const actionsMenuItems = () => {
    let actions: Action[] = []

    const renderActionButton = (label: string, onClick: React.MouseEventHandler<HTMLButtonElement>) => (
      <Button onClick={onClick} style={selectAllStyle} sx={{paddingRight: 2}}>
        {label}
      </Button>
    )

    if (selectedRepoIds.length === repositories.length && pageCount > 1) {
      actions.push({
        key: 'select-all',
        render: () => renderActionButton('Select all', () => toggleAllReposSelection(true, totalRepositoryCount)),
      })
    }

    if (orgHasRepos && selectedReposCount === totalRepositoryCount) {
      actions = [] // Empty the actions menu when "Clear selection" is needed
      actions.push({
        key: 'clear-selection',
        render: () => renderActionButton('Clear selection', () => toggleAllReposSelection(false, 0)),
      })
    }

    // If we uncheck a repo, we need to remove the clear selection button
    if (selectedRepoIds.length !== repositories.length) actions = []

    if (selectedRepoIds.length > 0) {
      actions.push({
        key: 'apply-configuration',
        render: isOverflowMenu => (
          <ActionMenu>
            {/* This adds a margin when the Button is rendered in the Overflow Menu  */}
            {/* https://github.com/github/security-products-growth/issues/380 */}
            <ActionMenu.Button sx={isOverflowMenu ? {marginX: 2} : {paddingRight: 2}}>
              Apply configuration
            </ActionMenu.Button>
            <ActionMenu.Overlay width="medium">
              <ActionList>
                {configs.map(config => (
                  <ActionList.Item
                    sx={{span: {fontWeight: 'bold'}}}
                    key={config.id}
                    onSelect={() =>
                      confirmConfigApplication(config, true, selectedReposCount === totalRepositoryCount, filterQuery)
                    }
                  >
                    {config.name}
                  </ActionList.Item>
                ))}
                <ActionList.Divider />
                <ActionList.Item onSelect={() => setDialogType('noConfig')}>
                  No configuration
                  <ActionList.Description variant="block">
                    <Text sx={{color: 'fg.muted'}}>
                      Detach configurations from selected repositories. This will not change repository settings.
                    </Text>
                  </ActionList.Description>
                </ActionList.Item>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        ),
      })
    }

    return actions
  }

  const searchBanner = () => {
    if (flashBannerType === 'searchTimedout') {
      return (
        <Flash variant="warning" {...testIdProps(flashBannerType)}>
          <Octicon icon={AlertIcon} />
          Search is taking too long to perform. Use fewer filters or try again.
        </Flash>
      )
    }

    return null
  }

  const metadata = (
    <>
      <ListViewMetadata
        title={<Text sx={{fontWeight: 'bold'}}>{pluralize('repository', totalRepositoryCount, true)}</Text>}
        onToggleSelectAll={(isSelectAllChecked: boolean) => {
          if (isSelectAllChecked) {
            toggleAllReposSelection(true, repositories.length)
          } else {
            toggleAllReposSelection(false, 0)
          }
        }}
        actionsLabel="Actions"
        actions={isQueryLoading ? [spinnerAction] : actionsMenuItems()}
      />
      {flashBannerType && searchBanner()}
    </>
  )

  const confirmConfigApplication = async (
    config: OrganizationSecurityConfiguration,
    overrideExistingConfig?: boolean,
    applyToAll?: boolean,
    repositoryFilterQuery?: string,
  ) => {
    setPendingConfigurationChanges({config, overrideExistingConfig, applyToAll, repositoryFilterQuery})
    setDialogType('confirmation')

    await confirmationSummary(
      setConfirmationDialogSummary,
      organization,
      renderContext,
      config.id,
      overrideExistingConfig,
      applyToAll,
      selectedRepoIds,
      filterQuery,
      config.enable_ghas,
    )
  }

  const applyPendingConfigurationChanges = async () => {
    const result = await applyConfiguration(
      pendingConfigurationChanges,
      renderContext,
      organization,
      navigate,
      'repos_table',
      selectedRepoIds,
    )

    if (result && result.status === 422) setDialogType('updateFailure')
  }

  const detachConfiguration = async (applyToAll: boolean, repositoryFilterQuery?: string) => {
    const result = await verifiedFetchJSON(settingsOrgSecurityProductsRepositoriesDeletePath({org: organization}), {
      method: 'DELETE',
      body: {repository_ids: applyToAll ? [] : selectedRepoIds, repository_query: repositoryFilterQuery},
    })
    if (result.ok) {
      toggleAllReposSelection(false, 0)
      setChangesInProgress({inProgress: true, type: 'applying_configuration'})
    }
  }

  const dialogMessages = () => {
    switch (dialogType) {
      case 'confirmation':
        return (
          <ConfirmationDialog
            confirmationDialogSummary={confirmationDialogSummary}
            pendingConfigurationChanges={pendingConfigurationChanges}
            hasPublicRepos={capabilities.hasPublicRepos}
            ghasPurchased={capabilities.ghasPurchased}
            docsBillingUrl={docsUrls.ghasBilling}
          />
        )
      case 'noConfig':
        return 'This will detach configurations from the selected repositories. This will not change the repository settings and future changes to the configuration will no longer affect selected repositories.'
      case 'updateFailure':
        return 'Another enablement is in progress. Please try again later.'
      default:
        return ''
    }
  }

  const dialogProps: Record<DialogType, DialogProps> = {
    confirmation: {
      'data-testid': 'confirmation-dialog',
      title: 'Apply configuration?',
      footerButtons: createDialogFooterButtons({
        cancelOnClick: () => {
          setDialogType(null)
          setConfirmationDialogSummary(null)
        },
        confirmOnClick: () => {
          applyPendingConfigurationChanges()
          toggleAllReposSelection(false, 0)
          setChangesInProgress({inProgress: true, type: 'applying_configuration'})
          setDialogType(null)
          setConfirmationDialogSummary(null)
        },
        confirmContent: 'Apply',
      }),
    },
    noConfig: {
      'data-testid': 'no-config-dialog',
      title: 'No configuration?',
      footerButtons: createDialogFooterButtons({
        cancelOnClick: () => setDialogType(null),
        confirmOnClick: () => {
          detachConfiguration(selectedReposCount === totalRepositoryCount, filterQuery)
          setDialogType(null)
          toggleAllReposSelection(false, 0)
        },
        confirmContent: 'No Configuration',
        confirmButtonType: 'danger',
      }),
    },
    updateFailure: {
      'data-testid': 'update-configuration-dialog',
      title: 'Unable to apply configuration',
      footerButtons: createDialogFooterButtons({
        confirmOnClick: () => setDialogType(null),
        confirmContent: 'Okay',
        confirmButtonType: 'default',
      }),
    },
  }

  return (
    <>
      {dialogType && (
        <Dialog {...dialogProps[dialogType]} onClose={() => setDialogType(null)} sx={dialogSize}>
          {dialogMessages()}
        </Dialog>
      )}
      <Box
        sx={{border: '1px solid', borderColor: 'border.muted', borderRadius: 2}}
        data-action-bar-item="spinner"
        data-testid="repos-list"
      >
        <ListView
          isSelectable={orgHasRepos}
          title="Repositories"
          titleHeaderTag="h2"
          singularUnits="repository"
          pluralUnits="repositories"
          metadata={metadata}
          selectedCount={selectedReposCount}
          totalCount={totalRepositoryCount}
        >
          <RepositoryRow />
        </ListView>
        {totalRepositoryCount < 1 && (
          <Blankslate>
            <Blankslate.Visual>
              <RepoIcon size={24} />
            </Blankslate.Visual>
            {filterQuery.trim() === ''
              ? 'This organization has no repositories.'
              : 'No repositories matched your search.'}
          </Blankslate>
        )}
      </Box>
    </>
  )
}

export default RepositoryTable
