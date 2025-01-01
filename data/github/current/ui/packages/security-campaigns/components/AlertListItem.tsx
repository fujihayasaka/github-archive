import {useMemo} from 'react'
import {AvatarStack, Label, Link, RelativeTime, Stack} from '@primer/react'
import {AlertIcon, CircleSlashIcon, CopilotIcon, NoteIcon, ShieldCheckIcon, ShieldIcon} from '@primer/octicons-react'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItem} from '@github-ui/list-view/ListItem'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {hovercardAttributesForActor} from '@github-ui/hovercards'
import {codeScanningAlertPath} from '@github-ui/paths'
import {
  type SecurityCampaignAlert,
  SecuritySeverity,
  RuleSeverity,
  type AlertParentLink,
} from '../types/security-campaign-alert'
import {AlertLinksButton} from './AlertLinksButton'
import {alertParentLinkHref} from '../utils/alert-parent-link'
import {AutofixLabel} from './AutofixLabel'
import {AutofixValidationChecksButton} from './AutofixValidationChecksButton'

import styles from './AlertListItem.module.css'
import {RepositoryLabel} from './RepositoryLabel'

export type AlertListItemProps = {
  alert: SecurityCampaignAlert
  isSelected?: boolean
  onSelect?: (isSelected: boolean) => void
  alertParentLink?: AlertParentLink
}

export function AlertListItem({alert, isSelected, onSelect, alertParentLink}: AlertListItemProps) {
  const icon = useMemo(() => {
    if (alert.isDismissed) {
      return {
        icon: ShieldCheckIcon,
        description: 'Status: Dismissed.',
        color: 'fg.muted',
      }
    }
    if (alert.isFixed) {
      return {
        icon: ShieldCheckIcon,
        description: 'Status: Fixed.',
        color: 'fg.muted',
      }
    }
    return {
      icon: ShieldIcon,
      description: 'Status: Open.',
      color: 'fg.muted',
    }
  }, [alert])

  const severityLabel = useMemo(() => {
    switch (alert.securitySeverity) {
      case SecuritySeverity.Low:
        return {
          variant: 'secondary' as const,
          label: 'Low',
        }
      case SecuritySeverity.Medium:
        return {
          variant: 'attention' as const,
          label: 'Medium',
        }
      case SecuritySeverity.High:
        return {
          variant: 'severe' as const,
          label: 'High',
        }
      case SecuritySeverity.Critical:
        return {
          variant: 'danger' as const,
          label: 'Critical',
        }
    }

    switch (alert.ruleSeverity) {
      case RuleSeverity.Note:
        return {
          variant: 'secondary' as const,
          label: 'Note',
          icon: NoteIcon,
          iconColor: 'color-fg-default' as const,
        }
      case RuleSeverity.Warning:
        return {
          variant: 'secondary' as const,
          label: 'Warning',
          icon: AlertIcon,
          iconColor: 'color-fg-attention' as const,
        }
      case RuleSeverity.Error:
        return {
          variant: 'secondary' as const,
          label: 'Error',
          icon: CircleSlashIcon,
          iconColor: 'color-fg-danger' as const,
        }
    }

    return undefined
  }, [alert])

  const getAlertResolutionFriendlyName = (resolution: string) => {
    switch (resolution) {
      case 'NO_RESOLUTION':
        return 'no resolution'
      case 'FALSE_POSITIVE':
        return 'false positive'
      case 'WONT_FIX':
        return "won't fix"
      case 'USED_IN_TESTS':
        return 'used in tests'
    }
  }

  const alertStatus = useMemo(() => {
    if (alert.isDismissed && alert.dismissedAt) {
      return (
        <>
          Closed as {getAlertResolutionFriendlyName(alert.resolution)}{' '}
          <RelativeTime datetime={alert.dismissedAt} format="relative" tense="past" />
        </>
      )
    }
    if (alert.isFixed && alert.fixedAt) {
      return (
        <>
          Closed as fixed <RelativeTime datetime={alert.fixedAt} format="relative" tense="past" />
        </>
      )
    }
    return (
      <>
        Opened <RelativeTime datetime={alert.createdAt} format="relative" tense="past" />
      </>
    )
  }, [alert])

  const repoLink = useMemo(
    () =>
      alertParentLinkHref(alertParentLink, {
        owner: alert.repository.ownerLogin,
        repo: alert.repository.name,
      }),
    [alert.repository.name, alert.repository.ownerLogin, alertParentLink],
  )

  return (
    <ListItem
      isSelected={isSelected}
      onSelect={onSelect}
      title={
        <ListItemTitle
          href={codeScanningAlertPath({
            owner: alert.repository.ownerLogin,
            repo: alert.repository.name,
            alertNumber: alert.number,
          })}
          value={alert.title}
          headingClassName={styles.ListItemTitle_0}
          containerClassName={styles.ListItemTitle_1}
        >
          {severityLabel && (
            <Label variant={severityLabel.variant}>
              {severityLabel.icon && (
                <span className={`pr-1 ${severityLabel.iconColor}`}>
                  <severityLabel.icon />
                </span>
              )}
              {severityLabel.label}
            </Label>
          )}
          {alert.hasSuggestedFix && <AutofixLabel validationChecks={alert.autofixValidationChecks} />}
        </ListItemTitle>
      }
      metadata={
        <ListItemMetadata alignment="left">
          {alert.hasSuggestedFix && alert.autofixValidationChecks && (
            <AutofixValidationChecksButton
              validationChecks={alert.autofixValidationChecks}
              repository={alert.repository}
            />
          )}
          <AlertLinksButton
            linkedPullRequests={alert.linkedPullRequests ?? []}
            linkedBranches={alert.linkedBranches ?? []}
            repository={alert.repository}
          />
          {alert.assignees && alert.assignees.length > 0 && (
            <AvatarStack alignRight size={20}>
              {alert.assignees.map(assignee => (
                <Link
                  key={assignee.id}
                  href={assignee.profilePath}
                  aria-label={assignee.isCopilot ? 'Copilot' : `View ${assignee.login}'s profile`}
                  {...hovercardAttributesForActor(assignee.login, {isCopilot: assignee.isCopilot})}
                >
                  {assignee.isCopilot ? (
                    <CopilotIcon className="color-fg-default" size={20} />
                  ) : (
                    <GitHubAvatar alt={assignee.login} src={assignee.avatarUrl} />
                  )}
                </Link>
              ))}
            </AvatarStack>
          )}
          {repoLink && (
            <Link muted href={repoLink}>
              <RepositoryLabel name={alert.repository.name} typeIcon={alert.repository.typeIcon} />
            </Link>
          )}
        </ListItemMetadata>
      }
    >
      <ListItemLeadingContent>
        <ListItemLeadingVisual {...icon} />
      </ListItemLeadingContent>
      <ListItemMainContent>
        <ListItemDescription>
          <Stack direction="horizontal" wrap="wrap" gap="none">
            <span className="mr-1 flex-nowrap">
              #{alert.number} &middot; {alertStatus} &middot; Detected by {alert.toolName}
            </span>
            <span className="flex-nowrap">
              {' '}
              in {alert.truncatedPath}:{alert.startLine}
            </span>
          </Stack>
        </ListItemDescription>
      </ListItemMainContent>
    </ListItem>
  )
}
