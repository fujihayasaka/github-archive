import {useCallback, useMemo, useRef, useState} from 'react'
import {ActionList, AnchoredOverlay, Button, Flash, Stack} from '@primer/react'
import type {ActionBarProps} from '@github-ui/action-bar'
import {AlertsListItems} from './AlertsListItems'
import {AlertsList} from './AlertsList'
import {AlertListItem} from './AlertListItem'
import {
  CreateBranchDialog,
  type BranchNextStep,
  type BranchType,
} from '@github-ui/code-scanning-shared/components/CreateBranchDialog'
import {BranchNextStepLocal} from '@github-ui/code-scanning-shared/components/BranchNextStepLocal'
import {BranchNextStepDesktop} from '@github-ui/code-scanning-shared/components/BranchNextStepDesktop'
import {BranchNextStepFlashes} from '@github-ui/code-scanning-shared/components/BranchNextStepFlashes'
import type {PullRequest} from '@github-ui/code-scanning-shared/types/pull-request'
import {CloseAlertOverlay} from './CloseAlertOverlay'
import {useRepoAlertsQuery} from '../hooks/use-repo-alerts-query'
import pluralize from 'pluralize'
import {ChevronDownIcon, CopilotIcon} from '@primer/octicons-react'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useNavigate} from '@github-ui/use-navigate'
import {useQueryClient} from '@github-ui/react-query'
import {useAlertsParams} from '../hooks/use-alerts-params'
import {
  pullRequestPath,
  securityCampaignRepoCreateBranchPath,
  securityCampaignRepoAssignToCopilotPath,
} from '@github-ui/paths'
import {useAssignToCopilot} from '../hooks/use-assign-to-copilot'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
import type {Repository} from '../types/repository'

export type RepoAlertsListProps = {
  alertsPath: string
  repository: Repository
  securityCampaignNumber: number
  canCreateBranch: boolean
  canCloseAlerts: boolean
  delegatedAlertDismissalEnabled: boolean
}

export function RepoAlertsList({
  alertsPath,
  repository,
  securityCampaignNumber,
  canCreateBranch,
  canCloseAlerts,
  delegatedAlertDismissalEnabled,
}: RepoAlertsListProps) {
  const [selectedItems, setSelectedItems] = useState<Set<number>>(() => new Set<number>())
  const onSelect = useCallback(
    (id: number, selected: boolean) => {
      setSelectedItems(prev => {
        const newSelectedItems = new Set<number>(prev)
        if (selected) {
          newSelectedItems.add(id)
        } else {
          newSelectedItems.delete(id)
        }
        return newSelectedItems
      })
    },
    [setSelectedItems],
  )

  const chooseBranchTypeAnchorRef = useRef(null)
  const [showChooseBranchType, setShowChooseBranchType] = useState(false)
  const [selectedBranchType, setSelectedBranchType] = useState<BranchType>('new')

  const [showCreateBranchDialog, setShowCreateBranchDialog] = useState(false)
  const [branchNextStep, setBranchNextStep] = useState<BranchNextStep>('none')
  const [newBranchName, setNewBranchName] = useState<string | null>(null)
  const [errorMessages, setErrorMessages] = useState<string[]>([])

  const handleChooseBranchType = (branchType: BranchType) => {
    setSelectedBranchType(branchType)
    setShowCreateBranchDialog(true)
  }

  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const handleCloseBranch = (
    nextStep: BranchNextStep,
    branchName: string | null,
    pullRequest: PullRequest | null,
    newErrorMessages?: string[],
  ) => {
    if (nextStep === 'pr' && pullRequest) {
      navigate(
        pullRequestPath({
          repo: pullRequest.repository,
          number: pullRequest.number,
        }),
      )
    } else {
      setShowCreateBranchDialog(false)
      setNewBranchName(branchName)
      setBranchNextStep(nextStep)
      setErrorMessages(newErrorMessages ?? [])
    }

    if (nextStep !== 'none') {
      queryClient.invalidateQueries({queryKey: ['repo-alerts', alertsPath]})
    }
  }

  const [showCloseAlertOverlay, setShowCloseAlertOverlay] = useState(false)

  const handleCloseAs = () => {
    setShowCloseAlertOverlay(true)
  }

  const handleBranchNextStepDialogClose = () => {
    setBranchNextStep('none')
    setSelectedItems(new Set())
  }

  const {query, cursor, onQueryChange, onCursorChange} = useAlertsParams()

  const onStateFilterChange = useCallback(
    (state: 'open' | 'closed' | 'all') => onQueryChange(`is:${state}`),
    [onQueryChange],
  )

  const alertsQuery = useRepoAlertsQuery(alertsPath, {query, cursor})
  const alerts = useMemo(() => alertsQuery.data?.alerts ?? [], [alertsQuery.data])

  const onToggleSelectAll = useCallback(
    (isSelectAllChecked: boolean) => {
      setSelectedItems(new Set<number>(isSelectAllChecked ? alerts.map(alert => alert.number) : []))
    },
    [setSelectedItems, alerts],
  )

  const selectedCount = selectedItems.size
  const closedSelectedAlertsCount = alerts.filter(
    alert => selectedItems.has(alert.number) && (alert.isDismissed || alert.isFixed),
  ).length
  const allSelectedAlertsAreClosed = selectedCount === closedSelectedAlertsCount
  const someSelectedAlertsAreClosed = closedSelectedAlertsCount > 0

  const selectedAlertsWithSuggestedFixes = alerts.filter(
    alert => selectedItems.has(alert.number) && alert.hasSuggestedFix,
  )
  const selectedItemsWithSuggestedFixes = selectedAlertsWithSuggestedFixes.map(alert => alert.number)
  const firstAlertWithSuggestedFixTitle = selectedAlertsWithSuggestedFixes[0]?.title ?? ''

  const handleCreateBranch = useCallback(() => {
    if (selectedItemsWithSuggestedFixes.length > 0) {
      setShowChooseBranchType(true)
    } else {
      setSelectedBranchType('new')
      setShowChooseBranchType(false)
      setShowCreateBranchDialog(true)
    }
  }, [selectedItemsWithSuggestedFixes.length])

  const isAgenticAutofixPadawanIntegrationEnabled = useFeatureFlag('code_scanning_agentic_autofix_padawan_integration')

  const {
    mutate: mutateAssignToCopilot,
    isPending: isAssignToCopilotPending,
    error: assignToCopilotError,
  } = useAssignToCopilot(
    securityCampaignRepoAssignToCopilotPath({
      owner: repository.ownerLogin,
      repo: repository.name,
      securityCampaignNumber,
    }),
  )

  const {showBanner} = useBannerContext()

  const handleAssignToCopilot = useCallback(async () => {
    // All selected alerts should have suggested fixes
    if (selectedItemsWithSuggestedFixes.length <= 0) {
      return
    }

    mutateAssignToCopilot(
      {
        alertNumbers: selectedItemsWithSuggestedFixes,
      },
      {
        onSuccess: () => {
          showBanner({
            message:
              'Successfully assigned to Copilot to apply the autofixes for selected alerts. Copilot will open a PR.',
            variant: 'success',
          })

          void queryClient.invalidateQueries({queryKey: ['repo-alerts', alertsPath]})
        },
      },
    )
  }, [selectedItemsWithSuggestedFixes, mutateAssignToCopilot, showBanner, queryClient, alertsPath])

  const actions = useMemo<ActionBarProps['actions']>(() => {
    if (selectedCount === 0) return []

    const visibleActions: ActionBarProps['actions'] = []

    // Assign to Copilot button
    if (isAgenticAutofixPadawanIntegrationEnabled) {
      visibleActions.push({
        key: 'assignToCopilot',
        render: (isOverflowMenu: boolean) => {
          return isOverflowMenu ? (
            <ActionList.Item
              loading={isAssignToCopilotPending}
              disabled={
                selectedCount === 0 ||
                selectedItemsWithSuggestedFixes.length !== selectedCount ||
                isAssignToCopilotPending
              }
              onSelect={handleAssignToCopilot}
            >
              <ActionList.LeadingVisual>
                <CopilotIcon />
              </ActionList.LeadingVisual>
              Assign to Copilot
            </ActionList.Item>
          ) : (
            <Button
              loading={isAssignToCopilotPending}
              disabled={
                selectedCount === 0 ||
                selectedItemsWithSuggestedFixes.length !== selectedCount ||
                isAssignToCopilotPending
              }
              onClick={handleAssignToCopilot}
              leadingVisual={CopilotIcon}
            >
              Assign to Copilot
            </Button>
          )
        },
      })
    }

    // Commit autofixes button
    if (canCreateBranch) {
      visibleActions.push({
        key: 'createBranch',
        render: isOverflowMenu => {
          const createBranchText =
            selectedItemsWithSuggestedFixes.length > 0
              ? `Commit ${pluralize('autofix', selectedItemsWithSuggestedFixes.length)}`
              : 'Create new branch'
          const textAndIcon = (
            <Stack direction="horizontal" align="center">
              {createBranchText} &nbsp;
              <ChevronDownIcon />
            </Stack>
          )
          if (isOverflowMenu) {
            return selectedItemsWithSuggestedFixes.length > 0 ? (
              <ActionList>
                <ActionList.Item onSelect={() => handleChooseBranchType('new')}>
                  Commit {pluralize('autofix', selectedItemsWithSuggestedFixes.length)} to new branch
                </ActionList.Item>
                <ActionList.Item onSelect={() => handleChooseBranchType('existing')}>
                  Commit {pluralize('autofix', selectedItemsWithSuggestedFixes.length)} to existing branch
                </ActionList.Item>
              </ActionList>
            ) : (
              <ActionList.Item
                ref={chooseBranchTypeAnchorRef}
                aria-haspopup={selectedItemsWithSuggestedFixes.length > 0}
                aria-expanded={showChooseBranchType}
                disabled={allSelectedAlertsAreClosed}
                onSelect={handleCreateBranch}
              >
                {textAndIcon}
              </ActionList.Item>
            )
          }

          return (
            <Button
              ref={chooseBranchTypeAnchorRef}
              aria-haspopup={selectedItemsWithSuggestedFixes.length > 0}
              aria-expanded={showChooseBranchType}
              disabled={allSelectedAlertsAreClosed}
              onClick={handleCreateBranch}
            >
              {textAndIcon}
            </Button>
          )
        },
      })
    }

    // Close Alerts button
    if (canCloseAlerts) {
      visibleActions.push({
        key: 'closeAlerts',
        render: (isOverflowMenu: boolean) => {
          return isOverflowMenu ? (
            <ActionList.Item
              aria-haspopup="true"
              aria-expanded={showCloseAlertOverlay}
              disabled={allSelectedAlertsAreClosed}
              onSelect={handleCloseAs}
            >
              Close alerts
            </ActionList.Item>
          ) : (
            <Button
              aria-haspopup="true"
              aria-expanded={showCloseAlertOverlay}
              disabled={allSelectedAlertsAreClosed}
              onClick={handleCloseAs}
            >
              Close alerts
            </Button>
          )
        },
      })
    }

    return visibleActions
  }, [
    canCloseAlerts,
    canCreateBranch,
    selectedItemsWithSuggestedFixes.length,
    allSelectedAlertsAreClosed,
    handleCreateBranch,
    selectedCount,
    showChooseBranchType,
    showCloseAlertOverlay,
    isAgenticAutofixPadawanIntegrationEnabled,
    handleAssignToCopilot,
    isAssignToCopilotPending,
  ])

  return (
    <>
      {assignToCopilotError && <Flash variant="danger">Something went wrong, please try again.</Flash>}
      <AlertsList
        onToggleSelectAll={onToggleSelectAll}
        openCount={alertsQuery.data?.openCount}
        closedCount={alertsQuery.data?.closedCount}
        prevCursor={alertsQuery.data?.prevCursor}
        nextCursor={alertsQuery.data?.nextCursor}
        isLoading={alertsQuery.isLoading}
        isError={alertsQuery.isError}
        query={query}
        onStateFilterChange={onStateFilterChange}
        showStateFilters={selectedCount === 0}
        onCursorChange={onCursorChange}
        setSelectedItems={setSelectedItems}
        isSelectable
        showLimitedAlertsWarning={false}
        actions={actions}
      >
        <AlertsListItems
          alerts={alerts}
          query={query}
          isLoading={alertsQuery.isLoading}
          isError={alertsQuery.isError}
          renderAlert={alert => (
            <AlertListItem
              alert={alert}
              onSelect={isSelected => onSelect(alert.number, isSelected)}
              isSelected={selectedItems.has(alert.number)}
            />
          )}
        />
      </AlertsList>
      {canCloseAlerts && showCloseAlertOverlay && (
        <CloseAlertOverlay
          setOpen={setShowCloseAlertOverlay}
          repository={repository}
          securityCampaignNumber={securityCampaignNumber}
          alertNumbers={Array.from(selectedItems)}
          delegatedAlertDismissalEnabled={delegatedAlertDismissalEnabled}
        />
      )}
      <AnchoredOverlay
        anchorRef={chooseBranchTypeAnchorRef}
        renderAnchor={null}
        open={showChooseBranchType}
        onOpen={() => setShowChooseBranchType(true)}
        onClose={() => setShowChooseBranchType(false)}
        focusZoneSettings={{disabled: true}}
        align="end"
      >
        <ActionList>
          <ActionList.Item onSelect={() => handleChooseBranchType('new')}>Commit to new branch</ActionList.Item>
          <ActionList.Item onSelect={() => handleChooseBranchType('existing')}>
            Commit to existing branch
          </ActionList.Item>
        </ActionList>
      </AnchoredOverlay>
      {canCreateBranch && showCreateBranchDialog && (
        <CreateBranchDialog
          firstAlertWithSuggestedFixTitle={firstAlertWithSuggestedFixTitle}
          alertNumbers={Array.from(selectedItems)}
          alertNumbersWithSuggestedFixes={selectedItemsWithSuggestedFixes}
          repository={repository}
          createPath={securityCampaignRepoCreateBranchPath({
            owner: repository.ownerLogin,
            repo: repository.name,
            securityCampaignNumber,
          })}
          onClose={handleCloseBranch}
          someSelectedAlertsAreClosed={someSelectedAlertsAreClosed}
          branchType={selectedBranchType}
          isCampaign
        />
      )}
      {branchNextStep === 'local' && (
        <BranchNextStepLocal
          branch={newBranchName}
          onClose={handleBranchNextStepDialogClose}
          flashes={<BranchNextStepFlashes errorMessages={errorMessages} />}
        />
      )}
      {branchNextStep === 'desktop' && (
        <BranchNextStepDesktop
          owner={repository.ownerLogin}
          repository={repository.name}
          branch={newBranchName}
          onClose={handleBranchNextStepDialogClose}
          flashes={<BranchNextStepFlashes errorMessages={errorMessages} />}
        />
      )}
    </>
  )
}
