import {useMemo} from 'react'
import {Box, Label, Link, RelativeTime, Text} from '@primer/react'
import {AlertIcon, CircleSlashIcon, NoteIcon, ShieldCheckIcon, ShieldIcon} from '@primer/octicons-react'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItem} from '@github-ui/list-view/ListItem'
import {codeScanningAlertPath} from '@github-ui/paths'
import {
  type SecurityCampaignAlert,
  SecuritySeverity,
  RuleSeverity,
  type AlertParentLink,
} from '../types/security-campaign-alert'
import {RepositoryLabel} from '@github-ui/security-campaigns-shared/components/RepositoryLabel'
import {AlertLinksButton} from './AlertLinksButton'

import styles from './AlertListItem.module.css'
import {alertParentLinkHref} from '../utils/alert-parent-link'

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
          iconColor: 'default' as const,
        }
      case RuleSeverity.Warning:
        return {
          variant: 'secondary' as const,
          label: 'Warning',
          icon: AlertIcon,
          iconColor: 'attention' as const,
        }
      case RuleSeverity.Error:
        return {
          variant: 'secondary' as const,
          label: 'Error',
          icon: CircleSlashIcon,
          iconColor: 'danger' as const,
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
          {alert.hasSuggestedFix && <Label variant="default">Autofix</Label>}
          {severityLabel && (
            <Label variant={severityLabel.variant}>
              {severityLabel.icon && (
                <Box as="span" sx={{pr: 1, color: `${severityLabel.iconColor}.fg`}}>
                  <severityLabel.icon />
                </Box>
              )}
              {severityLabel.label}
            </Label>
          )}
        </ListItemTitle>
      }
      metadata={
        <ListItemMetadata alignment="left">
          <AlertLinksButton
            linkedPullRequests={alert.linkedPullRequests ?? []}
            linkedBranches={alert.linkedBranches ?? []}
            repository={alert.repository}
          />
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
          <Box sx={{display: 'flex', flexWrap: 'wrap'}}>
            <Text flex-wrap="nowrap" sx={{mr: 1}}>
              #{alert.number} &middot; {alertStatus} &middot; Detected by {alert.toolName}
            </Text>
            <Text sx={{flexWrap: 'nowrap'}}>
              {' '}
              in {alert.truncatedPath}:{alert.startLine}
            </Text>
          </Box>
        </ListItemDescription>
      </ListItemMainContent>
    </ListItem>
  )
}
