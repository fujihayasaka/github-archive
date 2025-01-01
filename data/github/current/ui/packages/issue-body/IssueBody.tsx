import type {CommentBoxConfig} from '@github-ui/comment-box/CommentBox'
import type {Subject} from '@github-ui/comment-box/subject'
import styles from '@github-ui/commenting/AvatarStyles.module.css'
import {getQuotedText} from '@github-ui/commenting/quotes'
import {RefreshVideoWrapper} from '@github-ui/commenting/RefreshVideoWrapper'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {userHovercardPath} from '@github-ui/paths'
import type {SafeHTMLString} from '@github-ui/safe-html'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import {Box, Link} from '@primer/react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {graphql, useRelayEnvironment} from 'react-relay'
import {useFragment} from 'react-relay/hooks'

import type {IssueBody$key} from './__generated__/IssueBody.graphql'
import type {IssueBodyContent$key} from './__generated__/IssueBodyContent.graphql'
import type {IssueBodyRefetchQuery, IssueBodyRefetchQuery$data} from './__generated__/IssueBodyRefetchQuery.graphql'
import type {IssueBodySecondaryFragment$key} from './__generated__/IssueBodySecondaryFragment.graphql'
import type {IssueBodyHeaderSecondaryFragment$key} from './components/__generated__/IssueBodyHeaderSecondaryFragment.graphql'
import {IssueBodyEditor} from './components/IssueBodyEditor'
import {IssueBodyHeader} from './components/IssueBodyHeader'
import {IssueBodyViewer} from './components/IssueBodyViewer'
import {ERRORS} from './constants/errors'
import {LABELS} from './constants/labels'
import {TEST_IDS} from './constants/test-ids'
import {VALUES} from './constants/values'
import {useTaskListBlock} from './hooks/useTaskListBlock'
import type {updateIssueBodyMutation$data} from './mutations/__generated__/updateIssueBodyMutation.graphql'
import {commitUpdateIssueBodyMutation} from './mutations/update-issue-body-mutation'

type IssueBodyProps = {
  commentBoxConfig?: CommentBoxConfig
  onLinkClick?: (event: MouseEvent) => void
  onIssueUpdate?: () => void
  onIssueEditStateChange?: (isEditing: boolean) => void
  isIssueEditActive?: () => boolean
  onCommentReply: (quotedComment: string) => void
  highlightedEventText?: string
  issue: IssueBody$key
  insideSidePanel?: boolean
  secondaryKey?: IssueBodyHeaderSecondaryFragment$key | IssueBodySecondaryFragment$key
  copilotApiUrl?: string
}

const IssueBodySecondaryFragment = graphql`
  fragment IssueBodySecondaryFragment on Issue {
    viewerCanReport
    viewerCanReportToMaintainer
    viewerCanBlockFromOrg
    viewerCanUnblockFromOrg
  }
`

const IssueBodyRefetchQuery = graphql`
  query IssueBodyRefetchQuery($id: ID!) {
    node(id: $id) {
      ... on Issue {
        bodyHTML(unfurlReferences: true, renderTasklistBlocks: true)
      }
    }
  }
`

export function IssueBody({
  issue,
  secondaryKey,
  commentBoxConfig,
  onLinkClick,
  onIssueEditStateChange,
  onIssueUpdate,
  isIssueEditActive,
  onCommentReply,
  highlightedEventText,
  insideSidePanel,
  copilotApiUrl,
}: IssueBodyProps) {
  const data = useFragment(
    graphql`
      fragment IssueBody on Issue {
        id
        databaseId
        viewerDidAuthor
        locked
        title
        # eslint-disable-next-line relay/unused-fields
        author {
          ...IssueBodyHeaderActions
          ...IssueBodyHeaderAuthor
          avatarUrl
          login
          profileUrl
        }
        repository {
          databaseId
          nameWithOwner
          name
          slashCommandsEnabled
          id
          owner {
            login
            id
            url
          }
        }
        url
        viewerCanUpdateNext
        pendingBlock
        pendingUnblock
        ...IssueBodyViewer
        ...IssueBodyContent
        ...IssueBodyHeader
        ...IssueBodyHeader_issue
        ...IssueBodyViewerReactable
        ...IssueBodyViewerSubIssues
      }
    `,
    issue,
  )

  const {
    body: issueBody,
    bodyHTML,
    bodyVersion,
  } = useFragment(
    graphql`
      fragment IssueBodyContent on Issue {
        body
        bodyHTML(unfurlReferences: true, renderTasklistBlocks: true)
        bodyVersion
      }
    `,
    data as IssueBodyContent$key,
  )

  const secondaryData = useFragment(IssueBodySecondaryFragment, secondaryKey as IssueBodySecondaryFragment$key)

  const issueId = data.id
  const repositoryDatabaseId = data.repository.databaseId!

  const [presavedBody, setPresavedBody] = useSessionStorage<string | undefined>(
    VALUES.localStorageKeys.issueNewBody('hyperlist', issueId),
    undefined,
  )

  const [currentIssueBodyVersion, setCurrentIssueBodyVersion] = useState<string>(bodyVersion)
  const [bodyIsStale, setBodyIsStale] = useState(false)
  const [markdownBody, setMarkdownBody] = useState<string>(presavedBody || issueBody)
  const [isIssueBodyEditActive, setIsIssueBodyEditActive] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [defferedIsEditing, setDefferedIsEditing] = useState(false)
  const relayEnvironment = useRelayEnvironment()

  const issueBodyRef = useRef<HTMLDivElement>(null)

  const {addToast} = useToastContext()

  const onBodyChange = useCallback(
    (newMarkdown: string) => {
      setMarkdownBody(newMarkdown)
      setPresavedBody(newMarkdown)
      onIssueEditStateChange?.(true)
    },
    [onIssueEditStateChange, setPresavedBody],
  )

  useEffect(() => {
    // If the body version changes **after** the user started editing, keep using the previous body version
    if (defferedIsEditing) {
      return
    }
    // If the body version changes **before** the user started editing, update the current body version
    if (bodyVersion !== currentIssueBodyVersion) {
      setCurrentIssueBodyVersion(bodyVersion)
    }
  }, [bodyVersion, currentIssueBodyVersion, defferedIsEditing])

  useEffect(() => {
    if (!isIssueEditActive?.()) {
      setIsIssueBodyEditActive(false)
    }
  }, [isIssueEditActive, setIsIssueBodyEditActive])

  const subject = useMemo<Subject>(() => {
    return {
      type: 'issue',
      id: {
        id: data.id,
        databaseId: data.databaseId!,
      },
      repository: {
        databaseId: repositoryDatabaseId,
        nwo: data.repository.nameWithOwner,
        slashCommandsEnabled: data.repository.slashCommandsEnabled,
      },
    }
  }, [
    data.databaseId,
    data.id,
    data.repository.nameWithOwner,
    data.repository.slashCommandsEnabled,
    repositoryDatabaseId,
  ])

  const {viewerRef, onStartEdit, snapshot, isTasklistDirty} = useTaskListBlock({
    id: issueId,
    markdown: markdownBody,
    setMarkdown: setMarkdownBody,
    html: bodyHTML,
    isEditing: defferedIsEditing,
    bodyVersion: currentIssueBodyVersion,
  })

  const displayHtml = snapshot.length > 0 ? snapshot : bodyHTML

  useEffect(() => {
    if (isSubmitting) return

    if (isIssueBodyEditActive || isTasklistDirty) {
      return
    }

    setMarkdownBody(issueBody)

    return () => {
      setBodyIsStale(false)
      onIssueEditStateChange?.(false)
    }
  }, [isIssueBodyEditActive, isSubmitting, isTasklistDirty, issueBody, onIssueEditStateChange])

  useEffect(() => setIsIssueBodyEditActive(false), [issueId, setIsIssueBodyEditActive])

  useEffect(() => {
    setDefferedIsEditing(isIssueBodyEditActive)
    if (isIssueBodyEditActive) {
      onStartEdit()
    }
  }, [isIssueBodyEditActive, onStartEdit])

  const commitIssueBodyEdit = useCallback(() => {
    commitUpdateIssueBodyMutation({
      environment: relayEnvironment,
      input: {issueId, body: presavedBody ?? markdownBody, bodyVersion: currentIssueBodyVersion},
      onError: (error: Error) => {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: error.message.startsWith(LABELS.staleBodyErrorPrefix)
            ? ERRORS.couldNotUpdateIssueBodyStale
            : ERRORS.couldNotUpdateIssueBody,
        })

        if (error.message.startsWith(LABELS.staleBodyErrorPrefix)) {
          setIsIssueBodyEditActive(true)
          setIsSubmitting(false)
        } else {
          onIssueEditStateChange?.(false)
        }
      },
      onCompleted: (response: updateIssueBodyMutation$data) => {
        if (!response.updateIssue) {
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotUpdateIssueBody,
          })

          setIsIssueBodyEditActive(true)
          setIsSubmitting(false)
        } else {
          onIssueUpdate?.()
          setIsIssueBodyEditActive(false)
          onIssueEditStateChange?.(false)
          setIsSubmitting(false)
          if (response.updateIssue?.issue) {
            setCurrentIssueBodyVersion(response.updateIssue.issue.bodyVersion)
          }
          setPresavedBody(undefined)
        }
      },
    })
  }, [
    relayEnvironment,
    issueId,
    presavedBody,
    markdownBody,
    currentIssueBodyVersion,
    addToast,
    onIssueEditStateChange,
    onIssueUpdate,
    setPresavedBody,
  ])

  const handleOnReply = (quotedText?: string) => {
    onCommentReply(quotedText || getQuotedText(issueBody))
  }

  const highlighted = useMemo(() => {
    if (!highlightedEventText) return false
    return highlightedEventText === `#issue-${data.databaseId}`
  }, [highlightedEventText, data.databaseId])

  const highlightedStyling = useMemo(
    () =>
      highlighted
        ? {
            border: '1px solid',
            borderColor: 'accent.fg',
            borderRadius: '6px',
            boxShadow: `0px 0px 0px 1px var(--fgColor-accent, var(--color-accent-fg))`,
          }
        : {},
    [highlighted],
  )

  const url = `${data.url}#issue-${data.databaseId}`

  const {avatarUrl, login, profileUrl} = data.author ?? VALUES.ghost

  const getHTML = useCallback((fetchResult: Awaited<IssueBodyRefetchQuery$data> | undefined): string | undefined => {
    return fetchResult?.node?.bodyHTML
  }, [])

  return (
    <Box
      sx={{
        display: 'flex',
        gap: 3,
      }}
    >
      <Link
        href={profileUrl ?? undefined}
        data-hovercard-url={userHovercardPath({owner: login})}
        aria-label={`@${login}'s profile`}
        className={`${styles.avatarLink} ${styles.avatarOuter}`}
      >
        <GitHubAvatar src={avatarUrl} size={40} alt={`@${login}`} className={styles.issueViewerAvatar} />
      </Link>
      <Box
        ref={viewerRef}
        sx={{
          flexGrow: 1,
          order: [1, 1, 1, 1, 0],
          video: {
            aspectRatio: '16/9',
            width: '100%',
          },
          minWidth: 0,
          ...highlightedStyling,
        }}
        data-testid={TEST_IDS.issueBody}
        className={'react-issue-body'}
        data-hpc
      >
        <h2 className="sr-only">{LABELS.issueBodyHeader}</h2>
        <Box sx={{display: 'flex', flexDirection: 'row', gap: 2}}>
          <Box
            sx={{
              border: '1px solid',
              borderColor: data.viewerDidAuthor ? 'accent.muted' : 'border.default',
              borderRadius: 2,
              flexGrow: 1,
              width: '100%',
              minWidth: 0,
            }}
          >
            {defferedIsEditing || isSubmitting ? (
              <>
                <IssueBodyHeader
                  issue={data}
                  comment={data}
                  url={url}
                  secondaryKey={secondaryKey as IssueBodyHeaderSecondaryFragment$key}
                />
                <Box sx={{m: 2}}>
                  <IssueBodyEditor
                    editorDisabled={isSubmitting}
                    trailingIcon={!isSubmitting}
                    subjectId={issueId}
                    subject={subject}
                    body={presavedBody || markdownBody}
                    bodyIsStale={bodyIsStale}
                    onChange={onBodyChange}
                    onCancel={() => {
                      setIsIssueBodyEditActive(false)
                      setMarkdownBody(issueBody)
                      setPresavedBody(undefined)
                      onIssueEditStateChange?.(false)
                      setCurrentIssueBodyVersion(bodyVersion)
                    }}
                    onCommit={() => {
                      setIsSubmitting(true)
                      commitIssueBodyEdit()
                    }}
                    commentBoxConfig={commentBoxConfig}
                  />
                </Box>
              </>
            ) : (
              <>
                <IssueBodyHeader
                  issue={data}
                  comment={data}
                  url={url}
                  actionProps={{
                    viewerCanUpdate: data.viewerCanUpdateNext || false,
                    startIssueBodyEdit: () => {
                      setIsIssueBodyEditActive(true)
                    },
                    url,
                    issueBodyRef,
                    onReplySelect: handleOnReply,
                    viewerCanReport: secondaryData?.viewerCanReport ?? false,
                    viewerCanReportToMaintainer: secondaryData?.viewerCanReportToMaintainer ?? false,
                    issueId: data.id,
                    owner: data.repository.owner.login,
                    ownerId: data.repository.owner.id,
                    ownerUrl: data.repository.owner.url,
                    repoName: data.repository.name,
                    viewerCanBlockFromOrg: secondaryData?.viewerCanBlockFromOrg ?? false,
                    viewerCanUnblockFromOrg: secondaryData?.viewerCanUnblockFromOrg ?? false,
                    pendingBlock: data.pendingBlock ?? undefined,
                    pendingUnblock: data.pendingUnblock ?? undefined,
                    copilotApiUrl,
                  }}
                  secondaryKey={secondaryKey as IssueBodyHeaderSecondaryFragment$key}
                />
                <RefreshVideoWrapper<IssueBodyRefetchQuery>
                  bodyHTML={displayHtml as SafeHTMLString}
                  bodyRef={issueBodyRef}
                  id={issueId}
                  query={IssueBodyRefetchQuery}
                  getHTML={getHTML}
                >
                  <IssueBodyViewer
                    html={displayHtml as SafeHTMLString}
                    markdown={issueBody}
                    markdownViewerRef={viewerRef}
                    comment={data}
                    onLinkClick={onLinkClick}
                    issueBodyRef={issueBodyRef}
                    bodyVersion={currentIssueBodyVersion}
                    locked={data.locked}
                    reactable={data}
                    viewerCanUpdate={data.viewerCanUpdateNext || false}
                    subIssues={data}
                    title={data.title}
                    insideSidePanel={insideSidePanel}
                    repositoryId={data.repository.id}
                    onIssueEditStateChange={onIssueEditStateChange}
                    copilotApiUrl={copilotApiUrl}
                    nameWithOwner={data.repository.nameWithOwner}
                  />
                </RefreshVideoWrapper>
              </>
            )}
          </Box>
        </Box>
      </Box>
    </Box>
  )
}
