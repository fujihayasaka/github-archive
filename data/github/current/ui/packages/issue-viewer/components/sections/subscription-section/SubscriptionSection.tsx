import {Box, Button, Heading, Text} from '@primer/react'
import {Section} from '@github-ui/issue-metadata/Section'
import {ReadonlySectionHeader} from '@github-ui/issue-metadata/ReadonlySectionHeader'
import {useAlive} from '@github-ui/use-alive'
import {BellIcon, BellSlashIcon} from '@primer/octicons-react'
import {useCallback, useEffect, useState, useRef, useTransition} from 'react'
import {commitUpdateIssueSubscriptionMutation} from '../../../mutations/update-issue-subscription'
import {graphql, useFragment, useRefetchableFragment, useRelayEnvironment} from 'react-relay'
import {LABELS} from '../../../constants/labels'
import {ALIVE_REASONS} from '../../../constants/alive'
import type {SubscriptionSectionFragment$key} from './__generated__/SubscriptionSectionFragment.graphql'
import type {SubscriptionSectionRefetchableFragment$key} from './__generated__/SubscriptionSectionRefetchableFragment.graphql'
import {NotificationSettingsDialog} from './NotificationSettingsDialog'
import {clsx} from 'clsx'
import styles from './SubscriptionSection.module.css'
import type {IssueViewerViewer$data} from '../../__generated__/IssueViewerViewer.graphql'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export type SubscriptionSectionProps = {
  issue: SubscriptionSectionFragment$key | SubscriptionSectionRefetchableFragment$key
  viewer: IssueViewerViewer$data | null
}

export function SubscriptionSection({issue, viewer}: SubscriptionSectionProps) {
  const {threadSubscriptionChannel, id} = useFragment(
    graphql`
      fragment SubscriptionSectionFragment on Issue {
        id
        threadSubscriptionChannel
      }
    `,
    issue as SubscriptionSectionFragment$key,
  )

  // threadSubscriptionChannel should not be null for logged-in users, but check to ensure that it is loaded
  // because useAlive expects a valid channel name.
  return threadSubscriptionChannel ? (
    <SubscriptionSectionInternal
      issue={issue as SubscriptionSectionRefetchableFragment$key}
      id={id}
      threadSubscriptionChannel={threadSubscriptionChannel}
      viewer={viewer}
    />
  ) : null
}

export function SubscriptionSectionInternal({
  id,
  issue,
  threadSubscriptionChannel,
  viewer,
}: {
  id: string
  issue: SubscriptionSectionRefetchableFragment$key
  threadSubscriptionChannel: string
  viewer: IssueViewerViewer$data | null
}) {
  const [subscriptionAnnouncement, setSubscriptionAnnouncement] = useState<string>()
  const shouldUpdateAnnouncement = useRef(false)
  const environment = useRelayEnvironment()
  const [, startTransition] = useTransition()
  const [isDialogOpen, setIsDialogOpen] = useState(false)

  const updateSubscriptionAnnouncement = useCallback((newSubscribed: boolean, success = true) => {
    if (success) {
      // If it was successful, announce the change to the user
      setSubscriptionAnnouncement(
        newSubscribed ? LABELS.notifications.subscribedAnnouncement : LABELS.notifications.unsubscribedAnnouncement,
      )
    } else {
      setSubscriptionAnnouncement(LABELS.somethingWentWrong)
    }
  }, [])

  const [data, refetch] = useRefetchableFragment(
    graphql`
      fragment SubscriptionSectionRefetchableFragment on Issue
      @refetchable(queryName: "SubscriptionSectionRefetchableFragmentQuery")
      @argumentDefinitions(customised_notifications_enabled: {type: "Boolean!"}) {
        id
        viewerThreadSubscriptionFormAction
        viewerCustomSubscriptionEvents @include(if: $customised_notifications_enabled)
      }
    `,
    issue,
  )
  const {viewerThreadSubscriptionFormAction, viewerCustomSubscriptionEvents, id: issueId} = data
  const subscribed = viewerThreadSubscriptionFormAction === 'UNSUBSCRIBE'
  // Spreading this because it's 'readonly' and cannot be assigned to the mutable type 'ThreadSubscriptionEvent[]' when passing it to the Dialog
  const preSelectedCustomOptions = viewerCustomSubscriptionEvents ? [...viewerCustomSubscriptionEvents] : []

  const refreshSubscription = useCallback(() => {
    const query = () => {
      refetch(
        {},
        {
          fetchPolicy: 'network-only',
          onComplete: () => {
            shouldUpdateAnnouncement.current = true
          },
        },
      )
    }
    startTransition(() => query())
  }, [refetch, startTransition])

  useEffect(() => {
    if (shouldUpdateAnnouncement.current) {
      updateSubscriptionAnnouncement(subscribed)
      shouldUpdateAnnouncement.current = false
    }
  }, [subscribed, updateSubscriptionAnnouncement])

  const toggleSubscription = useCallback(() => {
    const newSubscribed = !subscribed
    commitUpdateIssueSubscriptionMutation({
      environment,
      input: {
        subscribableId: id,
        state: newSubscribed ? 'SUBSCRIBED' : 'UNSUBSCRIBED',
      },
      onCompleted: () => {
        updateSubscriptionAnnouncement(newSubscribed)
      },
      onError: () => updateSubscriptionAnnouncement(subscribed, false),
    })
  }, [environment, id, subscribed, updateSubscriptionAnnouncement])

  // Thread subscription updates are scoped to an individual user and emitted via signed user channels.
  useAlive(threadSubscriptionChannel, (event: {reason: string}) => {
    if (!event?.reason) return
    // Refetch subscription information if we receive a message that the subscription has changed.
    // We cannot rely on the "reason" to determine the new state, because we still receive a subscription
    // message if the thread is "ignored".
    if (event.reason === ALIVE_REASONS.SUBSCRIBED && !subscribed) {
      refreshSubscription()
    } else if (event.reason === ALIVE_REASONS.UNSUBSCRIBED && subscribed) {
      refreshSubscription()
    }
  })

  const buttonRef = useRef<HTMLButtonElement>(null)

  const sectionHeader = (
    <div className={clsx(styles.container)}>
      <Heading id={id} as="h3" className={clsx(styles.header)}>
        Notifications
      </Heading>
      <button onClick={() => setIsDialogOpen(true)} className={clsx(styles.button)} ref={buttonRef}>
        {LABELS.notifications.customizeNotificationsSettings}
      </button>
      {isDialogOpen && (
        <NotificationSettingsDialog
          title={LABELS.notifications.notificationsSettings}
          onClose={() => setIsDialogOpen(false)}
          returnFocusRef={buttonRef}
          threadId={issueId}
          preselectedViewerSubscriptionEvents={preSelectedCustomOptions}
          subscribed={subscribed}
        />
      )}
    </div>
  )

  // It controls whether email and web notifications for issues should be sent
  // via notifyd, and whether notifyd should be the primary source of truth
  // for issues related subscriptions and settings.
  const isNotifydEnabledIssuesWatchActivity = isFeatureEnabled('NOTIFYD_ISSUE_WATCH_ACTIVITY_NOTIFY')

  // Controls whether the settings for sending notifications for
  // participating activity should be written to notify
  const isNotifydEnabledIssuesThreadSubscription = isFeatureEnabled('NOTIFYD_ENABLE_ISSUE_THREAD_SUBSCRIPTIONS')

  // Both of the above flags are used in the backend logic of when to show the customise option: https://github.com/github/github/blob/66d24898297b3a2eba7133165ae6c2ab72c3f64a/packages/issues/app/models/issue/notifyd_adapter.rb#L26%7CIssue::NotifydAdapter
  // If they are both enabled, it means that the customisation option should not be shown
  const customizeDisabled =
    viewer?.isEnterpriseManagedUser || isNotifydEnabledIssuesThreadSubscription || isNotifydEnabledIssuesWatchActivity

  // Temporary FF to hide UI while backend work is in progress
  const showCustomizeNotificationSettings = isFeatureEnabled('ISSUES_REACT_CUSTOMISE_NOTIFICATIONS_UI')

  return (
    <Section
      sectionHeader={
        customizeDisabled || !showCustomizeNotificationSettings ? (
          <ReadonlySectionHeader title={LABELS.notifications.notificationsTitle} />
        ) : (
          sectionHeader
        )
      }
    >
      <Box sx={{display: 'flex', flexDirection: 'column', width: '100%', px: 2, pt: 2, alignItems: 'stretch'}}>
        <Button
          aria-describedby="issue-viewer-subscription-description"
          leadingVisual={subscribed ? BellSlashIcon : BellIcon}
          onClick={toggleSubscription}
        >
          {subscribed ? LABELS.notifications.subscribedButton : LABELS.notifications.unsubscribedButton}
        </Button>
        <Text id="issue-viewer-subscription-description" sx={{fontSize: 0, mb: 2, mt: 2, color: 'fg.muted'}}>
          {subscribed ? LABELS.notifications.subscribedDescription : LABELS.notifications.unsubscribedDescription}
        </Text>
        <span className="sr-only" aria-live="polite">
          {subscriptionAnnouncement}
        </span>
      </Box>
    </Section>
  )
}

export function SubscriptionSectionFallback() {
  return (
    <Section sectionHeader={<ReadonlySectionHeader title="Notifications" />}>
      <Box sx={{display: 'flex', flexDirection: 'column', width: '100%', px: 2, pt: 2, alignItems: 'stretch'}}>
        <Button aria-describedby="issue-viewer-subscription-description" leadingVisual={BellIcon}>
          {LABELS.notifications.unsubscribedButton}
        </Button>
        <Text id="issue-viewer-subscription-description" sx={{fontSize: 0, mb: 2, mt: 2, color: 'fg.muted'}}>
          {LABELS.notifications.unsubscribedDescription}
        </Text>
      </Box>
    </Section>
  )
}
