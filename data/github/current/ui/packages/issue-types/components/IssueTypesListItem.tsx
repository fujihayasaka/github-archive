import {Label} from '@primer/react'
import {type FC, useCallback, useRef, useState} from 'react'
import {IssueTypeItemMenu} from './IssueTypeItemMenu'
import {graphql, useFragment} from 'react-relay'
import type {IssueTypesListItem$key} from './__generated__/IssueTypesListItem.graphql'
import {DisableOrganizationConfirmationDialog} from './DisableOrganizationConfirmationDialog'
import {DeletionConfirmationDialog} from './DeletionConfirmationDialog'
import {useEnableDisableIssueType} from '../hooks/use-enable-disable-issue-type'
import {useIssueTypesAnalytics} from '../hooks/use-issue-types-analytics'
import {Resources} from '../constants/strings'
import styles from './IssueTypesListItem.module.css'
import {IssueTypeToken} from '@github-ui/issue-type-token'
import type {SetA11yAnnouncement} from '../types/shared-types'

type IssueTypesListItemProps = {
  issueType: IssueTypesListItem$key
  hasActions: boolean
  owner: string
  organizationId: string
  repositoryId?: string
  setA11yAnnouncement?: SetA11yAnnouncement
}

export const IssueTypesListItem: FC<IssueTypesListItemProps> = ({
  issueType,
  hasActions,
  owner,
  organizationId,
  setA11yAnnouncement,
}) => {
  const data = useFragment<IssueTypesListItem$key>(
    graphql`
      fragment IssueTypesListItem on IssueType {
        id
        name
        isEnabled
        description
        color
        ...DisableOrganizationConfirmationDialogIssueType
        ...DeletionConfirmationDialogIssueType
        ...IssueTypeItemMenuItem
      }
    `,
    issueType,
  )

  const [isDisableDialogOpen, setIsDisableDialogOpen] = useState<boolean>(false)
  const [isDeletionDialogOpen, setIsDeletionDialogOpen] = useState<boolean>(false)
  const {enableOrganizationIssueType} = useEnableDisableIssueType()
  const {sendIssueTypesAnalyticsEvent} = useIssueTypesAnalytics()
  const anchorIconRef = useRef<HTMLButtonElement>(null)

  const getTypeTokenTooltipText = (isTruncated: boolean) => (isTruncated ? data.name : undefined)

  const onToggleClick = useCallback(() => {
    setA11yAnnouncement?.(null)
    if (data.isEnabled) {
      setIsDisableDialogOpen(true)
    } else {
      sendIssueTypesAnalyticsEvent('org_issue_type.enable', 'ORG_ISSUE_TYPE_LIST_ITEM_MENU_OPTION', {
        issueTypeId: data.id,
      })
      enableOrganizationIssueType(data.id, () => setA11yAnnouncement?.(Resources.enabledIssueTypeSuccess))
    }
  }, [data.id, data.isEnabled, enableOrganizationIssueType, sendIssueTypesAnalyticsEvent, setA11yAnnouncement])

  return (
    <li
      data-testid={data.id}
      className={`${styles.itemContainer} flex-md-nowrap`}
      aria-label={Resources.ariaLabel.issueTypeListItem(data.name)}
    >
      <div className={styles.itemTokenWrapper}>
        <IssueTypeToken
          name={data.name}
          color={data.color}
          getTooltipText={getTypeTokenTooltipText}
          href={`/organizations/${owner}/settings/issue-types/${data.id}`}
        />
      </div>
      {data.description && (
        <span className={`${styles.itemDescription} ${!data.isEnabled && styles.spacer}`}>{data.description}</span>
      )}
      {!data.isEnabled && (
        <div className={styles.itemMetadataWrapper}>{!data.isEnabled && <Label>Disabled</Label>}</div>
      )}
      <div className={styles.actionsWrapper}>
        {hasActions && (
          <IssueTypeItemMenu
            ref={anchorIconRef}
            issueType={data}
            toggleIssueType={onToggleClick}
            handleDelete={() => setIsDeletionDialogOpen(true)}
            owner={owner || ''}
          />
        )}
      </div>
      {isDisableDialogOpen && (
        <DisableOrganizationConfirmationDialog
          closeDialog={() => setIsDisableDialogOpen(false)}
          issueType={data}
          returnFocusRefDisable={anchorIconRef}
          setA11yAnnouncement={setA11yAnnouncement}
        />
      )}
      {owner && isDeletionDialogOpen && (
        <DeletionConfirmationDialog
          owner={owner}
          organizationId={organizationId}
          closeDialog={() => setIsDeletionDialogOpen(false)}
          issueType={data}
          returnFocusRefDeletion={anchorIconRef}
          redirectOnDeletion={false}
          setA11yAnnouncement={setA11yAnnouncement}
        />
      )}
    </li>
  )
}
