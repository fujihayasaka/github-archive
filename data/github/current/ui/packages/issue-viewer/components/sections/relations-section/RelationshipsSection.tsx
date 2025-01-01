import {ActionList, ActionMenu, CounterLabel, Label, Link} from '@primer/react'
import {graphql, type PreloadedQuery, useFragment, usePreloadedQuery, useRelayEnvironment} from 'react-relay'

import {LABELS} from '../../../constants/labels'
import {Section} from '@github-ui/issue-metadata/Section'
import {ParentIssue} from './ParentIssue'
import {RepositoryAndIssuePicker} from '@github-ui/item-picker/RepositoryAndIssuePicker'
import type React from 'react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {setParentMutation} from '../../../mutations/set-parent-mutation'
import {SectionHeader} from '@github-ui/issue-metadata/SectionHeader'
import {ReadonlySectionHeader} from '@github-ui/issue-metadata/ReadonlySectionHeader'
import type {IssuePickerItem} from '@github-ui/item-picker/IssuePicker'
import {commitRemoveSubIssueMutation} from '@github-ui/sub-issues/commitRemoveSubIssueMutation'
import type {RelationshipsSectionFragment$key} from './__generated__/RelationshipsSectionFragment.graphql'
import type {RelationshipsSectionQuery} from './__generated__/RelationshipsSectionQuery.graphql'
import {GlobalCommands, CommandActionListItem} from '@github-ui/ui-commands'
import {useAlert} from '@github-ui/sub-issues/useAlert'
import {useCanEditSubIssues} from '@github-ui/sub-issues/useCanEditSubIssues'

import styles from './RelationshipsSection.module.css'
import {DependencyIssue} from './DependencyIssue'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {DependenciesPicker, type DependenciesPickerProps} from './DependenciesPicker'
import {RelationshipsViewAllButton} from './RelationshipsViewAllButton'
import {LazyRelationshipsBlockedByListView} from './LazyRelationshipsBlockedByListView'
import {LazyRelationshipsBlockingListView} from './LazyRelationshipsBlockingListView'
import {RelationshipsAlertDialog} from '../../shared/RelationshipsAlertDialog'
import {useDependencyAlerts} from '../../../hooks/use-dependencies-alert'
import {Banner} from '@primer/react/experimental'
import {LockIcon} from '@primer/octicons-react'
import {isStaff} from '@github-ui/stats'

const VISIBLE_ISSUES_THRESHOLD = 3
type DependenciesPickerState = DependenciesPickerProps['type'] | null

export const RelationshipsSectionGraphqlQuery = graphql`
  query RelationshipsSectionQuery($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      issue(number: $number) {
        ...RelationshipsSectionFragment
      }
    }
  }
`

const RelationshipsSectionFragment = graphql`
  fragment RelationshipsSectionFragment on Issue {
    id
    repository {
      nameWithOwner
      owner {
        login
      }
    }
    parent {
      id
      ...ParentIssueFragment
    }
    topBlockedBy: blockedBy(first: 3, ranked: true) {
      nodes {
        id
        ...DependencyIssueFragment
      }
      pageInfo {
        hasNextPage
      }
    }
    topBlocking: blocking(first: 3, ranked: true) {
      nodes {
        id
        ...DependencyIssueFragment
      }
      pageInfo {
        hasNextPage
      }
    }
    issueDependenciesSummary {
      blockedBy
      blocking
    }
    ...useCanEditSubIssues
  }
`

type RelationshipsSectionProps = {
  queryRef: PreloadedQuery<RelationshipsSectionQuery>
  onLinkClick?: (event: MouseEvent) => void
  insideSidePanel?: boolean
}

type RelationshipsSectionInternalProps = Omit<RelationshipsSectionProps, 'queryRef'> & {
  issue: RelationshipsSectionFragment$key
  insideSidePanel?: boolean
}

function checkForInaccessibleIssues(totalIssuesCount: number, visibleIssuesCount: number, isLastPage: boolean) {
  // if we have more total issues than what's visible then we have hidden issues.
  const hasHiddenIssues = totalIssuesCount > visibleIssuesCount

  // if fewer than 3 issues are visible, it means there are hidden/private issues.
  // if exactly 3 issues are visible (which is the maximum per page), and there's no next page of results, it also indicates that some issues are private.
  const issuesAreHiddenDueToPrivacy =
    visibleIssuesCount < VISIBLE_ISSUES_THRESHOLD || (visibleIssuesCount === VISIBLE_ISSUES_THRESHOLD && isLastPage)

  return hasHiddenIssues && issuesAreHiddenDueToPrivacy
}

export function RelationshipsSectionFallback() {
  return (
    <Section
      sectionHeader={<ReadonlySectionHeader title={LABELS.sectionTitles.relationships} />}
      emptyText={LABELS.emptySections.relationships}
    />
  )
}

export function RelationshipsSection({queryRef, ...rest}: RelationshipsSectionProps) {
  const preloadedData = usePreloadedQuery<RelationshipsSectionQuery>(RelationshipsSectionGraphqlQuery, queryRef)
  return preloadedData.repository && preloadedData.repository.issue ? (
    <RelationshipsSectionInternal issue={preloadedData.repository.issue} {...rest} />
  ) : null
}

export function RelationshipsSectionInternal({issue, onLinkClick, insideSidePanel}: RelationshipsSectionInternalProps) {
  const fragmentIssue = useFragment(RelationshipsSectionFragment, issue)
  const {parent, topBlockedBy, topBlocking, repository, id, issueDependenciesSummary} = fragmentIssue

  const {issue_dependencies} = useFeatureFlags()
  const environment = useRelayEnvironment()
  const {alert, resetAlert, showServerAlert} = useAlert()
  const {
    alerts: dependencyAlerts,
    resetAlerts: resetDependencyAlerts,
    setAlertsFromErrors: setDependencyAlertsFromErrors,
  } = useDependencyAlerts()
  const [menuOpen, setMenuOpen] = useState<boolean>(false)
  const [pickerType, setPickerType] = useState<'Issue' | 'Repository' | null>(null)
  const [dependenciesPickerState, setDependenciesPickerState] = useState<DependenciesPickerState>(null)
  const canEditSubIssues = useCanEditSubIssues(fragmentIssue)

  useEffect(() => {
    if (menuOpen) {
      setPickerType(null)
      setDependenciesPickerState(null)
    }
  }, [menuOpen])

  const onDependenciesPickerClose = useCallback(() => {
    setDependenciesPickerState(null)
  }, [])

  /**
   * When the issue-viewer is rendered within the side-panel, two issue-viewers are rendered at a time. This results
   * in `<GlobalCommands>` activating both pickers at once. To remedy this, we check if the side-panel is open and
   * whether or not the current issue-viewer is within the side-panel.
   *
   * If insideSidePanel is false, the issue-viewer is not inside the open side-panel.
   * If insideSidePanel is undefined, the side panel is not open.
   */
  const shouldAcceptCommand = insideSidePanel || insideSidePanel === undefined

  const onIssueSelection = useCallback(
    (selectedIssue: IssuePickerItem[]) => {
      if (!selectedIssue[0]) {
        // No selected issue means that an issue was deselected, so we remove the parent if there is one
        if (parent) {
          commitRemoveSubIssueMutation({
            environment,
            input: {
              issueId: parent.id,
              subIssueId: id,
            },
          })
        }
      } else {
        setParentMutation({
          environment,
          input: {
            subIssueId: id,
            issueId: selectedIssue[0].id,
            replaceParent: true,
          },
          onError: error => {
            showServerAlert(error)
          },
        })
      }
    },
    [environment, id, parent, showServerAlert],
  )

  const onPickerTypeChange = useCallback((t: 'Issue' | 'Repository' | null) => setPickerType(t), [setPickerType])

  const hasBlockedBy = topBlockedBy?.nodes && topBlockedBy.nodes.length > 0
  const hasBlocking = topBlocking?.nodes && topBlocking.nodes.length > 0

  const hasViewAllBlockedBy = topBlockedBy?.pageInfo?.hasNextPage
  const hasViewAllBlocking = topBlocking?.pageInfo?.hasNextPage

  const hasInaccessibleBlockedByIssues = useMemo(() => {
    const totalBlockedByCount = issueDependenciesSummary.blockedBy || 0
    const visibleIssuesCount = topBlockedBy?.nodes?.length || 0
    const isLastPage = !topBlockedBy?.pageInfo?.hasNextPage

    return checkForInaccessibleIssues(totalBlockedByCount, visibleIssuesCount, isLastPage)
  }, [issueDependenciesSummary, topBlockedBy])

  const hasInaccessibleBlockingIssues = useMemo(() => {
    const totalBlockingCount = issueDependenciesSummary.blocking || 0
    const visibleIssuesCount = topBlocking?.nodes?.length || 0
    const isLastPage = !topBlocking?.pageInfo?.hasNextPage

    return checkForInaccessibleIssues(totalBlockingCount, visibleIssuesCount, isLastPage)
  }, [issueDependenciesSummary, topBlocking])

  const hasContent = useMemo(() => {
    if (!issue_dependencies) {
      return parent
    }
    return parent || issueDependenciesSummary.blockedBy || issueDependenciesSummary.blocking
  }, [issue_dependencies, parent, issueDependenciesSummary])

  const sectionHeaderRef = useRef<HTMLButtonElement | null>(null)
  return (
    <Section
      emptyText={hasContent ? undefined : LABELS.emptySections.relationships}
      sectionHeader={
        <>
          {shouldAcceptCommand && (
            <GlobalCommands
              commands={{
                'issue-viewer:edit-parent': () => {
                  // Close relationship type menu in case it's open
                  setMenuOpen(false)
                  setPickerType('Issue')
                },
                'issue-viewer:mark-blocked-by': () => {
                  if (!issue_dependencies) {
                    return
                  }
                  setMenuOpen(false)
                  setDependenciesPickerState('blockedBy')
                },
                'issue-viewer:mark-blocking': () => {
                  if (!issue_dependencies) {
                    return
                  }
                  setMenuOpen(false)
                  setDependenciesPickerState('blocking')
                },
              }}
            />
          )}
          {/* We render the section header separate of both the picker and the action menu that will anchor to it.
              we set up a ref for those other elements to use to anchor to instead */}
          <SectionHeader
            ref={sectionHeaderRef}
            buttonProps={{
              onClick: () => setMenuOpen(o => !o),
            }}
            readonly={!canEditSubIssues}
            title={LABELS.sectionTitles.relationships}
          />
          <RepositoryAndIssuePicker
            onPickerTypeChange={onPickerTypeChange}
            selectedIssueIds={parent ? [parent.id] : []}
            hiddenIssueIds={[id]}
            onIssueSelection={onIssueSelection}
            organization={repository.owner.login}
            defaultRepositoryNameWithOwner={repository.nameWithOwner}
            pickerType={pickerType}
            // As currently designed, the ItemPicker requires an element to render as the anchor. This gets eventually
            // passed down to the SelectPanel which will handle rendering this element. In reality though, we don't want
            // this component to be responsible for rendering an element, we just want it to attach to the ref to an
            // existing anchor, so we do that here and return an empty element to "render"
            anchorElement={props => {
              const {ref} = props as {
                ref: React.MutableRefObject<HTMLButtonElement | null>
              }
              if (ref) {
                ref.current = sectionHeaderRef.current
              }
              // We don't actually want to render any element, as we are relying on the rendered section header above
              return <></>
            }}
          />
          {issue_dependencies && dependenciesPickerState && (
            <DependenciesPicker
              type={dependenciesPickerState}
              onClose={onDependenciesPickerClose}
              issueId={id}
              organization={repository.owner.login}
              defaultRepositoryNameWithOwner={repository.nameWithOwner}
              anchorRef={sectionHeaderRef}
              onError={setDependencyAlertsFromErrors}
            />
          )}
          {issue_dependencies && dependencyAlerts.length > 0 && (
            <RelationshipsAlertDialog
              title={`Failed to save ${dependencyAlerts.length} ${dependencyAlerts.length > 1 ? 'issues' : 'issue'}`}
              onClose={resetDependencyAlerts}
              width="large"
              data-testid="dependency-alert-dialog"
            >
              {dependencyAlerts.map((dependencyAlert, i) => (
                <Banner
                  // Index is unfortunately the only unique property we have of this alert
                  // eslint-disable-next-line @eslint-react/no-array-index-key
                  key={i}
                  variant="critical"
                  className={styles.DependencyErrorBanner}
                  aria-label={dependencyAlert.title}
                >
                  <Banner.Title>{dependencyAlert.title}</Banner.Title>
                  <Banner.Description>{dependencyAlert.body}</Banner.Description>
                </Banner>
              ))}
            </RelationshipsAlertDialog>
          )}
          <ActionMenu open={menuOpen} onOpenChange={open => setMenuOpen(open)} anchorRef={sectionHeaderRef}>
            <ActionMenu.Overlay width="medium">
              <ActionList>
                <ActionList.Group>
                  <CommandActionListItem commandId="issue-viewer:edit-parent">
                    {parent ? 'Change or remove parent' : 'Add parent'}
                  </CommandActionListItem>
                  {issue_dependencies && (
                    <CommandActionListItem commandId="issue-viewer:mark-blocked-by">
                      {hasBlockedBy ? 'Change blocked by' : 'Mark as blocked by'}
                    </CommandActionListItem>
                  )}
                  {issue_dependencies && (
                    <CommandActionListItem commandId="issue-viewer:mark-blocking">
                      {hasBlocking ? 'Change blocking' : 'Mark as blocking'}
                    </CommandActionListItem>
                  )}
                </ActionList.Group>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </>
      }
    >
      {alert && (
        <RelationshipsAlertDialog title={alert.title} onClose={resetAlert}>
          {alert.body}
        </RelationshipsAlertDialog>
      )}
      <ActionList variant="full" className={styles.ActionList_Relationship_Overrides}>
        {parent && (
          <ActionList.Group>
            <ActionList.GroupHeading as="h4" className={styles.ActionList_GroupHeading}>
              {LABELS.relationNames.parentIssue}
            </ActionList.GroupHeading>
            <ParentIssue onLinkClick={onLinkClick} issueKey={parent} />
          </ActionList.Group>
        )}
        {issue_dependencies && issueDependenciesSummary.blockedBy > 0 && (
          <>
            {parent && <ActionList.Divider className={styles.ActionList_Divider} />}
            <ActionList.Group>
              <ActionList.GroupHeading as="h4" className={styles.ActionList_GroupHeading}>
                {LABELS.relationNames.blockedByIssues}
                {issueDependenciesSummary.blockedBy > 0 && (
                  <CounterLabel className={styles.RelationshipCountLabel} scheme="secondary">
                    {issueDependenciesSummary.blockedBy}
                  </CounterLabel>
                )}
                <StaffFeedback />
              </ActionList.GroupHeading>
              {hasBlockedBy &&
                topBlockedBy.nodes
                  .filter(i => !!i)
                  .map(blockedIssue => (
                    <DependencyIssue key={blockedIssue.id} onLinkClick={onLinkClick} issueKey={blockedIssue} />
                  ))}
              {hasInaccessibleBlockedByIssues && (
                <ActionList.Item disabled aria-disabled="true">
                  <ActionList.LeadingVisual>
                    <LockIcon size={16} />
                  </ActionList.LeadingVisual>
                  <span className="text-small fgColor-muted" data-testid="private-blocked-by-notice">
                    Private issues are hidden.
                  </span>
                </ActionList.Item>
              )}
              {hasViewAllBlockedBy && (
                <RelationshipsViewAllButton
                  dialogTitle={LABELS.relationNames.blockedByIssues}
                  countOpenItems={issueDependenciesSummary.blockedBy}
                >
                  <LazyRelationshipsBlockedByListView itemId={id} blockedByCount={issueDependenciesSummary.blockedBy} />
                </RelationshipsViewAllButton>
              )}
            </ActionList.Group>
          </>
        )}
        {issue_dependencies && hasBlocking && (
          <>
            {(parent || hasBlockedBy) && <ActionList.Divider className={styles.ActionList_Divider} />}
            <ActionList.Group>
              <ActionList.GroupHeading as="h4" className={styles.ActionList_GroupHeading}>
                {LABELS.relationNames.blockingIssues}
                {issueDependenciesSummary.blocking > 0 && (
                  <CounterLabel className={styles.RelationshipCountLabel} scheme="secondary">
                    {issueDependenciesSummary.blocking}
                  </CounterLabel>
                )}
                {!hasBlockedBy && <StaffFeedback />}
              </ActionList.GroupHeading>
              {topBlocking.nodes
                .filter(i => !!i)
                .map(blockingIssue => (
                  <DependencyIssue key={blockingIssue.id} onLinkClick={onLinkClick} issueKey={blockingIssue} />
                ))}
              {hasInaccessibleBlockingIssues && (
                <ActionList.Item disabled aria-disabled="true">
                  <ActionList.LeadingVisual>
                    <LockIcon size={16} />
                  </ActionList.LeadingVisual>
                  <span className="text-small fgColor-muted" data-testid="private-blocking-notice">
                    Private issues are hidden.
                  </span>
                </ActionList.Item>
              )}
              {hasViewAllBlocking && (
                <RelationshipsViewAllButton
                  dialogTitle={LABELS.relationNames.blockingIssues}
                  countOpenItems={issueDependenciesSummary.blocking}
                >
                  <LazyRelationshipsBlockingListView itemId={id} blockingCount={issueDependenciesSummary.blocking} />
                </RelationshipsViewAllButton>
              )}
            </ActionList.Group>
          </>
        )}
      </ActionList>
    </Section>
  )
}

const StaffFeedback = () => {
  if (!isStaff()) {
    return null
  }
  return (
    <>
      <Link
        className={styles.StaffFeedback_Link}
        target="_blank"
        href="https://gh.io/dependencies-feedback"
        data-testid="staff-feedback"
      >
        <span className={styles.StaffFeedback_linkText}>Give feedback</span>
        <Label variant="accent">Staff</Label>
      </Link>
    </>
  )
}
