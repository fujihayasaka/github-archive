import {useCommentEditsContext} from '@github-ui/commenting/CommentEditsContext'
import {IssueCommentComposer} from '@github-ui/commenting/IssueCommentComposer'
import type {MarkdownComposerRef} from '@github-ui/commenting/useMarkdownBody'
import {VALUES} from '@github-ui/commenting/Values'
import {useItemPickersContext} from '@github-ui/item-picker/ItemPickersContext'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import PreloadedQueryBoundary from '@github-ui/relay-preloaded-query-boundary'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {SubIssuesList} from '@github-ui/sub-issues/SubIssuesList'
import {useCanEditSubIssues} from '@github-ui/sub-issues/useCanEditSubIssues'
import {useHasSubIssues} from '@github-ui/sub-issues/useHasSubIssues'
import {useContainerBreakpoint} from '@github-ui/use-container-breakpoint'
import {Box, Heading} from '@primer/react'
import {Suspense, useCallback, useEffect, useMemo, useRef} from 'react'
import {graphql, type PreloadedQuery, usePreloadedQuery, useQueryLoader} from 'react-relay'
import {useFragment} from 'react-relay/hooks'

import {IssueBody} from '@github-ui/issue-body/IssueBody'

import type {LazyContributorFooter$key} from '@github-ui/contributor-footer/LazyContributorFooter.graphql'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'

import {SubIssuesCreateDialog} from '@github-ui/sub-issues/SubIssuesCreateDialog'
import {useSubIssueState} from '@github-ui/sub-issues/SubIssueStateContext'
import {ISSUE_EVENTS} from '@github-ui/timeline-items/Events'
import {getHighlightedEventText} from '@github-ui/timeline-items/HighlightedEvent'
import {LABELS} from '@github-ui/timeline-items/Labels'
import {useBeforeUnload} from 'react-router-dom'
import {CLASS_NAMES} from '../constants/class-names'
import {IDS} from '../constants/ids'
import {TEST_IDS} from '../constants/test-ids'
import {useInputElementActiveContext} from '../contexts/InputElementActiveContext'
import {useHash} from '../hooks/use-hash'
import type {ItemIdentifier} from '../types/issue'
import type {IssueViewerIssue$key} from './__generated__/IssueViewerIssue.graphql'
import type {IssueViewerSecondaryIssueData$data} from './__generated__/IssueViewerSecondaryIssueData.graphql'
import type {IssueViewerSecondaryViewQueryRepoData$data} from './__generated__/IssueViewerSecondaryViewQueryRepoData.graphql'
import type {IssueViewerViewer$key} from './__generated__/IssueViewerViewer.graphql'
import type {IssueViewerViewQuery} from './__generated__/IssueViewerViewQuery.graphql'
import {ContentWrapper} from './ContentWrapper'
import {ConvertedToDiscussionBanner} from './ConvertedToDiscussionBanner'
import {EmuContributionBlockedBanner} from './EmuContributionBlockedBanner'
import {Header} from './header/Header'
import {IssueSidebar} from './IssueSidebar'
import {IssueTimelineErrorFallback} from './IssueTimelineErrorFallback'
import {IssueTimelineLoading} from './IssueTimelineLoading'
import {IssueViewerLoading} from './IssueViewerLoading'
import {useSecondaryQuery} from './IssueViewerSecondaryView'
import {ISSUE_VIEWER_DEFAULT_CONFIG, type OptionConfig} from './OptionConfig'
import {renderIssueViewerErrors} from './shared/IssueViewerError'
import {SignedOutBanner} from './SignedOutBanner'
import {IssueTimeline} from './timeline/IssueTimeline'
import styles from './IssueViewer.module.css'

export type IssueViewerQueries = {
  issueViewerViewQuery: IssueViewerViewQuery
}

type IssueViewerProps = {
  itemIdentifier: ItemIdentifier
  optionConfig?: OptionConfig
}

type IssueViewerSecondaryDataProps = {
  secondaryIssueData?: IssueViewerSecondaryIssueData$data
  secondaryRepoData?: IssueViewerSecondaryViewQueryRepoData$data
}

type IssueViewerInternalProps = {
  optionConfig: OptionConfig
  issueViewerViewRef: PreloadedQuery<IssueViewerViewQuery>
  containerRef: React.RefObject<HTMLDivElement>
} & IssueViewerSecondaryDataProps

type IssueViewerInternalFragmentProps = {
  optionConfig: OptionConfig
  viewerFragment: IssueViewerViewer$key | null
  issueFragment: IssueViewerIssue$key
  containerRef: React.RefObject<HTMLDivElement>
  isRepoOwnerEnterpriseManaged?: boolean | null
} & IssueViewerSecondaryDataProps

type IssueViewerWithSecondaryProps = IssueViewerInternalProps & {
  owner: string
  repo: string
  number: number
}

export const IssueViewerSecondaryIssueDataFragment = graphql`
  fragment IssueViewerSecondaryIssueData on Issue {
    ...HeaderSecondary
    ...HeaderParentTitle
    ...IssueCommentComposerSecondary
    ...IssueTimelineSecondary
    ...IssueSidebarLazySections
    ...IssueSidebarSecondary
    # eslint-disable-next-line relay/must-colocate-fragment-spreads
    ...TaskListStatusFragment
    # eslint-disable-next-line relay/must-colocate-fragment-spreads
    ...TrackedByFragment
    ...IssueBodyHeaderSecondaryFragment
    ...IssueBodySecondaryFragment
    # sub-issues
    ...SubIssuesList
    ...SubIssuesCreateDialog
    ...HeaderSubIssueSummary @arguments(fetchSubIssues: true)
    discussion {
      url
    }
  }
`

export const IssueViewerViewGraphqlQuery = graphql`
  query IssueViewerViewQuery($repo: String!, $owner: String!, $number: Int!, $allowedOwner: String) {
    repository(name: $repo, owner: $owner) {
      isOwnerEnterpriseManaged
      issue(number: $number) @required(action: THROW) {
        ...IssueViewerIssue @arguments(allowedOwner: $allowedOwner)
      }
    }
    safeViewer {
      ...IssueViewerViewer
    }
  }
`

const issueViewerViewFragment = graphql`
  fragment IssueViewerIssue on Issue @argumentDefinitions(allowedOwner: {type: "String", defaultValue: null}) {
    id
    # eslint-disable-next-line relay/unused-fields the updatedAt field is used for an experiment to count the different version of an issue
    updatedAt
    ...Header
    ...IssueBody
    ...IssueCommentComposer
    ...IssueSidebarPrimaryQuery @arguments(allowedOwner: $allowedOwner)
    ...IssueTimelineIssueFragment
    # sub-issues
    ...HeaderSubIssueSummary @arguments(fetchSubIssues: false)
    ...useHasSubIssues
    ...useCanEditSubIssues
  }
`
export const issueViewerViewerFragment = graphql`
  fragment IssueViewerViewer on User {
    # Is needed to be passed to the IssueSidebar and the SubscriptionSection component in order not to show the notification customization option for EMU
    # eslint-disable-next-line relay/unused-fields
    isEnterpriseManagedUser
    enterpriseManagedEnterpriseId
    login
    ...IssueCommentComposerViewer
    # this is intentional to have the current viewer preloaded for the item pickers
    # eslint-disable-next-line relay/must-colocate-fragment-spreads this is required by the item pickers
    ...AssigneePickerAssignee
  }
`

export function IssueViewer({itemIdentifier, optionConfig = ISSUE_VIEWER_DEFAULT_CONFIG}: IssueViewerProps) {
  const {repo, owner, number} = itemIdentifier

  const [issueViewerViewRef, loadIssueViewerView] = useQueryLoader<IssueViewerViewQuery>(
    IssueViewerViewGraphqlQuery,
    optionConfig.preloadedQueries?.issueViewerViewQuery,
  )
  const issueViewerContainerRef = useRef<HTMLDivElement>(null)

  const fetchPolicy = optionConfig.issueQueriesFetchingPolicy?.fetchPolicy
  const {sub_issues} = useFeatureFlags()

  useEffect(() => {
    if (!optionConfig.preloadedQueries?.issueViewerViewQuery) {
      loadIssueViewerView(
        {
          owner,
          repo,
          number,
          allowedOwner: optionConfig.allowedProjectOwner ?? null,
        },
        {fetchPolicy},
      )
    }
  }, [
    loadIssueViewerView,
    owner,
    repo,
    optionConfig.preloadedQueries?.issueViewerViewQuery,
    optionConfig.allowedProjectOwner,
    fetchPolicy,
    number,
    sub_issues,
  ])

  if (!issueViewerViewRef) return <IssueViewerLoading optionConfig={optionConfig} />

  return (
    <PreloadedQueryBoundary
      key={`${owner}-${repo}-${number}`}
      onRetry={() =>
        loadIssueViewerView(
          {
            owner,
            repo,
            number,
            allowedOwner: optionConfig.allowedProjectOwner ?? null,
          },
          {fetchPolicy: 'network-only'},
        )
      }
      fallback={renderIssueViewerErrors}
      critical
    >
      <Box
        className={styles.issueViewerContainer}
        ref={issueViewerContainerRef}
        sx={{
          display: 'flex',
          flex: 'auto',
          flexDirection: 'column',
          justifyContent: 'stretch',
          alignItems: 'center',
          position: 'relative',
          pt: 3,
        }}
      >
        <Suspense fallback={<IssueViewerLoading optionConfig={optionConfig} />}>
          <IsssueViewerWithSecondary
            owner={owner}
            repo={repo}
            number={number}
            issueViewerViewRef={issueViewerViewRef}
            containerRef={issueViewerContainerRef}
            optionConfig={optionConfig}
          />
        </Suspense>
      </Box>
    </PreloadedQueryBoundary>
  )
}

function IssueViewerInternal({
  issueViewerViewRef,
  containerRef,
  optionConfig,
  secondaryIssueData,
  secondaryRepoData,
}: IssueViewerInternalProps) {
  const {repository, safeViewer} = usePreloadedQuery<IssueViewerViewQuery>(
    IssueViewerViewGraphqlQuery,
    issueViewerViewRef,
  )

  return repository?.issue ? (
    <IssueViewerInternalFragment
      viewerFragment={safeViewer || null}
      issueFragment={repository.issue}
      containerRef={containerRef}
      optionConfig={optionConfig}
      isRepoOwnerEnterpriseManaged={repository.isOwnerEnterpriseManaged}
      secondaryIssueData={secondaryIssueData}
      secondaryRepoData={secondaryRepoData}
    />
  ) : null
}

export function IssueViewerInternalFragment({
  viewerFragment,
  issueFragment,
  optionConfig,
  containerRef,
  isRepoOwnerEnterpriseManaged,
  secondaryIssueData,
  secondaryRepoData,
}: IssueViewerInternalFragmentProps) {
  const issue = useFragment(issueViewerViewFragment, issueFragment)
  const viewer = useFragment(issueViewerViewerFragment, viewerFragment) || null

  const hasSubIssues = useHasSubIssues(issue)
  const canEditSubIssues = useCanEditSubIssues(issue)

  const showEmuContributionBlockedBanner =
    viewer && !!viewer.enterpriseManagedEnterpriseId && !isRepoOwnerEnterpriseManaged
  const showCommentComposer = viewer && !showEmuContributionBlockedBanner

  const composerRef = useRef<MarkdownComposerRef>(null)
  const {startCommentEdit, cancelCommentEdit, isCommentEditActive} = useCommentEditsContext()
  const issueBodyKey = `issue-${issue.id}-body`
  const {setInputElementState, clearInputElementStates} = useInputElementActiveContext()
  const {anyItemPickerOpen} = useItemPickersContext()
  const breakpoint = useContainerBreakpoint(containerRef.current)

  const {sub_issues} = useFeatureFlags()

  // Reset comment and input states on issue change
  useEffect(() => {
    clearInputElementStates()
  }, [issue.id, clearInputElementStates])

  useEffect(() => {
    setInputElementState(IDS.itemPicker, anyItemPickerOpen())
  }, [anyItemPickerOpen, setInputElementState])

  // Whenever the issue body editing state changes, synchronize that state via callbacks
  const onIssueEditStateChange = optionConfig.onIssueEditStateChange
  useEffect(() => {
    onIssueEditStateChange?.(isCommentEditActive())
  }, [isCommentEditActive, onIssueEditStateChange])

  const onCommentReply = useCallback((quotedComment: string) => {
    composerRef.current?.setText(quotedComment)
    setTimeout(() => composerRef.current?.focus(), 0)
  }, [])

  const onCommentChange = useCallback(
    (id: string) => {
      startCommentEdit(VALUES.localStorageKeys.issueComment('', issue.id, id))
      optionConfig.onCommentEditStart?.(id)
    },
    [issue.id, optionConfig, startCommentEdit],
  )
  const onCommentEditCancel = useCallback(
    (id: string) => {
      cancelCommentEdit(VALUES.localStorageKeys.issueComment('', issue.id, id))
      optionConfig.onCommentEditCancel?.(id)
    },
    [cancelCommentEdit, issue.id, optionConfig],
  )

  const beforeUnload = useCallback(
    (event: BeforeUnloadEvent) => {
      if (isCommentEditActive()) {
        event.preventDefault()
        return (event.returnValue = '')
      }
    },
    [isCommentEditActive],
  )

  useBeforeUnload(beforeUnload)

  const metadataContent = useMemo(
    () => (
      <IssueSidebar
        sidebarKey={issue}
        sidebarSecondaryKey={secondaryIssueData}
        viewer={viewer}
        optionConfig={optionConfig}
      />
    ),
    [issue, optionConfig, secondaryIssueData, viewer],
  )

  const metadataPane = useMemo(
    () => (
      <div className={styles.issueViewerMetadataPane} data-testid={TEST_IDS.issueViewerMetadataPane}>
        <Heading as="h2" className={styles.metadataHeader}>
          {LABELS.metadataHeader}
        </Heading>
        <Heading as="h2" className={`${styles.largeScreenMetadataHeader} sr-only`}>
          {LABELS.metadataHeader}
        </Heading>
        {metadataContent}
      </div>
    ),
    [metadataContent],
  )

  const handleBodyEditStateChange = useCallback(
    (isEditing: boolean) => {
      optionConfig?.onIssueEditStateChange?.(isEditing)
      if (isEditing) {
        startCommentEdit(issueBodyKey)
      } else {
        cancelCommentEdit(issueBodyKey)
      }
    },
    [cancelCommentEdit, issueBodyKey, optionConfig, startCommentEdit],
  )
  // This is used to subscribe to hash-change events
  // Specifically, it is used to detect when the user has (soft) navigated to a comment in the same issue
  useHash()

  const {createDialogOpen, activeIssueId, closeCreateDialog} = useSubIssueState()

  return (
    <>
      {secondaryIssueData?.discussion && (
        <ConvertedToDiscussionBanner discussionUrl={secondaryIssueData?.discussion?.url ?? ''} />
      )}
      <Header
        issue={issue}
        issueSecondary={secondaryIssueData}
        optionConfig={optionConfig}
        containerRef={containerRef}
      />
      <ContentWrapper sx={optionConfig?.innerSx}>
        <Box
          sx={{
            display: 'flex',
            flex: 'auto',
            flexDirection: optionConfig.useViewportQueries
              ? ['column', 'column', 'row', 'row']
              : breakpoint(['column', 'column', 'row', 'row']),
            justifyContent: 'stretch',
            gap: [2, 2, 2, 4],
          }}
        >
          <Box
            sx={{
              width: optionConfig.useViewportQueries
                ? ['100%', '100%', 'auto', 'auto']
                : breakpoint(['100%', '100%', 'auto', 'auto']),
              backgroundColor: 'canvas.default',
              zIndex: 1,
              flexGrow: 1,
              minWidth: 0,
            }}
          >
            <div data-testid={TEST_IDS.issueViewerIssueContainer}>
              <IssueBody
                issue={issue}
                commentBoxConfig={optionConfig.commentBoxConfig}
                secondaryKey={secondaryIssueData}
                onLinkClick={optionConfig.onLinkClick}
                onIssueEditStateChange={handleBodyEditStateChange}
                onIssueUpdate={optionConfig.onIssueUpdate}
                onCommentReply={onCommentReply}
                isIssueEditActive={isCommentEditActive}
                highlightedEventText={ssrSafeLocation.hash}
                insideSidePanel={optionConfig.insideSidePanel}
              />
            </div>
            {!!sub_issues && hasSubIssues && (
              <Box
                sx={{my: 2, ml: breakpoint(['0px', '0px', '56px', '56px'])}}
                data-testid={TEST_IDS.subIssuesIssueContainer}
              >
                <SubIssuesList
                  issueKey={secondaryIssueData}
                  onSubIssueClick={optionConfig.onSubIssueClick}
                  insideSidePanel={optionConfig.insideSidePanel}
                  readonly={!canEditSubIssues}
                />
              </Box>
            )}
            <div data-testid={TEST_IDS.issueViewerCommentsContainer} className={CLASS_NAMES.commentsContainer}>
              <Box
                sx={{
                  mb: 3,
                }}
              >
                <ErrorBoundary fallback={<IssueTimelineErrorFallback />} critical>
                  <Suspense fallback={<IssueTimelineLoading delayedShow />}>
                    <IssueTimeline
                      issue={issue}
                      issueSecondary={secondaryIssueData}
                      viewer={viewer?.login ?? null}
                      highlightedEvent={getHighlightedEventText(ssrSafeLocation.hash, ISSUE_EVENTS)}
                      onCommentReply={onCommentReply}
                      onCommentChange={onCommentChange}
                      onCommentEditCancel={onCommentEditCancel}
                      optionConfig={optionConfig}
                    />
                    {showCommentComposer && (
                      <IssueCommentComposer
                        ref={composerRef}
                        issue={issue}
                        issueSecondary={secondaryIssueData}
                        repoSecondary={secondaryRepoData as LazyContributorFooter$key}
                        viewer={viewer}
                        onChange={() => {
                          startCommentEdit(VALUES.localStorageKeys.issueNewComment('viewer', issue.id))
                          optionConfig.onCommentEditStart?.(IDS.newComment)
                        }}
                        onSave={() => {
                          cancelCommentEdit(VALUES.localStorageKeys.issueNewComment('viewer', issue.id))
                          optionConfig.onCommentEditCancel?.(IDS.newComment)
                        }}
                        onCancel={() => {
                          cancelCommentEdit(VALUES.localStorageKeys.issueNewComment('viewer', issue.id))
                          optionConfig.onCommentEditCancel?.(IDS.newComment)
                        }}
                        onNewIssueComment={optionConfig.onNewIssueComment}
                        commentBoxConfig={optionConfig.commentBoxConfig}
                        singleKeyShortcutEnabled={optionConfig.singleKeyShortcutsEnabled || false}
                        insideSidePanel={optionConfig.insideSidePanel}
                      />
                    )}
                    {!viewer && <SignedOutBanner />}
                  </Suspense>
                </ErrorBoundary>
                {showEmuContributionBlockedBanner && <EmuContributionBlockedBanner />}
              </Box>
            </div>
          </Box>

          <Box
            sx={{
              width: optionConfig.useViewportQueries
                ? ['auto', 'auto', '256px', '296px']
                : breakpoint(['auto', 'auto', '256px', '296px']),
              flexShrink: 0,
            }}
            data-testid={TEST_IDS.issueViewerMetadataContainer}
          >
            {metadataPane}
          </Box>
        </Box>
      </ContentWrapper>
      {secondaryIssueData && createDialogOpen && activeIssueId === issue.id && (
        <SubIssuesCreateDialog
          open={createDialogOpen}
          setOpen={closeCreateDialog}
          issue={secondaryIssueData}
          onCreateSuccess={({createMore}): void => {
            if (!createMore) {
              closeCreateDialog()
            }
          }}
        />
      )}
    </>
  )
}

function IsssueViewerWithSecondary({owner, repo, number, ...rest}: IssueViewerWithSecondaryProps) {
  const [secondaryIssueData, secondaryRepoData] = useSecondaryQuery({owner, repo, number})

  return (
    <IssueViewerInternal
      secondaryIssueData={secondaryIssueData ?? undefined}
      secondaryRepoData={secondaryRepoData ?? undefined}
      {...rest}
    />
  )
}
