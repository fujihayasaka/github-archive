import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {Suspense, useMemo, useState, useCallback} from 'react'
import {ApplyLabelsBulkAction} from '@github-ui/issues-bulk-actions/ApplyLabelsBulkAction'
import {ApplyAssigneesBulkAction} from '@github-ui/issues-bulk-actions/ApplyAssigneesBulkAction'
import {BulkMarkAs} from '@github-ui/issues-bulk-actions/BulkMarkAs'
import {AddToProjectsBulkAction} from '@github-ui/issues-bulk-actions/AddToProjectsBulkAction'
import {ApplyMilestoneBulkAction} from '@github-ui/issues-bulk-actions/ApplyMilestoneBulkAction'
import {ApplyIssueTypeBulkAction} from '@github-ui/issues-bulk-actions/ApplyIssueTypeBulkAction'
import {noop} from '@github-ui/noop'
import type {Action} from '@github-ui/action-bar'
import {useListViewSelection} from '@github-ui/list-view/ListViewSelectionContext'
import {useListViewMultiPageSelection} from '@github-ui/list-view/ListViewMultiPageSelectionContext'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import type {ListItemsHeaderProps, ScopedRepository, ItemNodeType} from '../types'

import {LABELS} from '../constants/labels'
import {VALUES} from '../constants/values'
import {
  type Icon,
  RocketIcon,
  TagIcon,
  TriangleDownIcon,
  PeopleIcon,
  ProjectSymlinkIcon,
  IssueOpenedIcon,
  MilestoneIcon,
} from '@primer/octicons-react'
import {ActionList, Button} from '@primer/react'
import {AnalyticsProvider} from '@github-ui/analytics-provider'

function ListItemsHeaderBulkFallback() {
  const renderFake = useCallback((isOverflowing: boolean, LeadingVisual: Icon, anchorText: string) => {
    if (isOverflowing) {
      return (
        <ActionList.Item disabled>
          <ActionList.LeadingVisual>
            <LeadingVisual />
          </ActionList.LeadingVisual>
          {anchorText}
          <ActionList.TrailingVisual>
            <TriangleDownIcon />
          </ActionList.TrailingVisual>
        </ActionList.Item>
      )
    }

    return (
      <Button disabled leadingVisual={LeadingVisual} trailingVisual={TriangleDownIcon}>
        {anchorText}
      </Button>
    )
  }, [])

  // This array should be in sync with the actions array populating the actual component
  const actions = useMemo(
    () => [
      {
        key: 'mark-as',
        render: (isOverflowMenu: boolean) => renderFake(isOverflowMenu, VALUES.issueIcons.CLOSED.icon, LABELS.markAs),
      },
      {
        key: 'apply-labels',
        render: (isOverflowMenu: boolean) => renderFake(isOverflowMenu, TagIcon, LABELS.label),
      },
      {
        key: 'apply-assignees',
        render: (isOverflowMenu: boolean) => renderFake(isOverflowMenu, PeopleIcon, LABELS.assign),
      },
      {
        key: 'add-to-projects',
        render: (isOverflowMenu: boolean) => renderFake(isOverflowMenu, ProjectSymlinkIcon, LABELS.project),
      },
      {
        key: 'apply-milestone',
        render: (isOverflowMenu: boolean) => renderFake(isOverflowMenu, MilestoneIcon, LABELS.milestone),
      },
      {
        key: 'apply-issue-type',
        render: (isOverflowMenu: boolean) => renderFake(isOverflowMenu, IssueOpenedIcon, LABELS.setIssueType),
      },
    ],
    [renderFake],
  )

  return (
    <ListViewMetadata onToggleSelectAll={noop} actionsLabel={LABELS.bulkActions} actions={actions} density={'normal'} />
  )
}

export const ListItemsHeaderWithBulkActions = ({
  checkedItems,
  issueNodes,
  setCheckedItems,
  updateListHasPRs,
  useBulkActions,
  scopedRepository,
  singleKeyShortcutsEnabled,
  bulkJobId,
  setBulkJobId,
  isInOrganization,
}: ListItemsHeaderProps & {scopedRepository: ScopedRepository}) => {
  const {addToast, addPersistedToast} = useToastContext()
  const {setSelectedCount} = useListViewSelection()
  const {setMultiPageSelectionAllowed} = useListViewMultiPageSelection()
  const [isBulkActionRunning, setIsBulkActionRunning] = useState(bulkJobId !== null)
  const isIssueNode = (node: ItemNodeType): node is ItemNodeType => node.__typename === 'Issue'

  const issuesToActOn: ItemNodeType[] = Array.from(checkedItems.values())
    .filter(v => v != null)
    .filter(isIssueNode)

  const bulkActionCompleted = useCallback(
    (jobId?: string) => {
      setIsBulkActionRunning(false)
      if (jobId) {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addPersistedToast({
          type: 'info',
          message: 'Updating issues', //LABELS.updatingIssues,
          icon: <RocketIcon />,
          role: 'status',
        })
        setBulkJobId(jobId)
      }
    },
    [addPersistedToast, setBulkJobId],
  )

  const bulkActionError = useCallback(
    (error: Error) => {
      setIsBulkActionRunning(false)
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: `Could not update issues: ${error.message}`,
      })
    },
    [addToast],
  )

  const sharedActionProps = useMemo(
    () => ({
      //we don't support bulk actions on queries. It is usually useful to fetch all ids by query (select all type of functionality) but this feature is generally disabled due to the load that could put on server
      useQueryForAction: false,
      onCompleted: bulkActionCompleted,
      onError: bulkActionError,
      disabled: isBulkActionRunning,
      issuesToActOn: issuesToActOn.filter(node => node != null).map(node => node.id),
      singleKeyShortcutsEnabled: singleKeyShortcutsEnabled || false,
    }),
    [bulkActionCompleted, bulkActionError, isBulkActionRunning, issuesToActOn, singleKeyShortcutsEnabled],
  )

  const onToggleSelectAll = useCallback(
    (isSelectAllChecked: boolean) => {
      if (isSelectAllChecked) {
        setCheckedItems(
          issueNodes.filter(node => node != null).reduce((map, node) => map.set(node.id, node), new Map()),
        )
        updateListHasPRs(
          issueNodes.filter(node => node != null).reduce((map, node) => map.set(node.id, node), new Map()),
        )
      } else {
        setCheckedItems(new Map())
        setSelectedCount(0)
        setMultiPageSelectionAllowed?.(false)
      }
    },
    [issueNodes, setCheckedItems, setMultiPageSelectionAllowed, setSelectedCount, updateListHasPRs],
  )

  const shouldRenderBulkActions = scopedRepository && useBulkActions

  const analyticsMetadata = useMemo(
    () => ({
      owner: scopedRepository?.owner ?? '',
      repositoryName: scopedRepository?.name ?? '',
    }),
    [scopedRepository?.name, scopedRepository?.owner],
  )

  const actions = useMemo<Action[] | undefined>(() => {
    if (!shouldRenderBulkActions) return
    const issueIds = issuesToActOn.map(i => i.id)
    const actionList = [
      {
        key: 'mark-as',
        render: (isOverflowMenu: boolean) => <BulkMarkAs {...sharedActionProps} nested={isOverflowMenu} />,
      },
      {
        key: 'apply-labels',
        render: (isOverflowMenu: boolean) => (
          <ApplyLabelsBulkAction
            owner={scopedRepository.owner}
            repo={scopedRepository.name}
            nested={isOverflowMenu}
            issueIds={issueIds}
            {...sharedActionProps}
            repositoryId={scopedRepository?.id}
          />
        ),
      },
      {
        key: 'apply-assignees',
        render: (isOverflowMenu: boolean) => (
          <ApplyAssigneesBulkAction
            nested={isOverflowMenu}
            issueIds={issueIds}
            {...sharedActionProps}
            repositoryId={scopedRepository?.id}
            owner={scopedRepository?.owner}
            repo={scopedRepository?.name}
          />
        ),
      },
      {
        key: 'add-to-projects',
        render: (isOverflowMenu: boolean) => (
          <AddToProjectsBulkAction
            nested={isOverflowMenu}
            issueIds={issueIds}
            repositoryId={scopedRepository?.id}
            owner={scopedRepository?.owner}
            repo={scopedRepository?.name}
            {...sharedActionProps}
          />
        ),
      },
      {
        key: 'apply-milestone',
        render: (isOverflowMenu: boolean) => (
          <ApplyMilestoneBulkAction
            owner={scopedRepository.owner}
            repo={scopedRepository.name}
            nested={isOverflowMenu}
            issueIds={issuesToActOn.map(i => i.id)}
            repositoryId={scopedRepository.id}
            {...sharedActionProps}
          />
        ),
      },
    ]

    if (isInOrganization)
      actionList.push({
        key: 'apply-issue-type',
        render: (isOverflowMenu: boolean) => (
          <AnalyticsProvider appName="issue_types" category="issues_index" metadata={analyticsMetadata}>
            <ApplyIssueTypeBulkAction
              owner={scopedRepository.owner}
              repo={scopedRepository.name}
              nested={isOverflowMenu}
              issueIds={issueIds}
              repositoryId={scopedRepository?.id}
              {...sharedActionProps}
            />
          </AnalyticsProvider>
        ),
      })

    return actionList
  }, [
    sharedActionProps,
    scopedRepository?.id,
    scopedRepository?.owner,
    scopedRepository?.name,
    issuesToActOn,
    shouldRenderBulkActions,
    analyticsMetadata,
    isInOrganization,
  ])

  return (
    <Suspense fallback={<ListItemsHeaderBulkFallback />}>
      <ListViewMetadata
        onToggleSelectAll={onToggleSelectAll}
        actionsLabel={LABELS.bulkActions}
        actions={actions}
        density={'normal'}
        {...sharedActionProps}
      />
    </Suspense>
  )
}
