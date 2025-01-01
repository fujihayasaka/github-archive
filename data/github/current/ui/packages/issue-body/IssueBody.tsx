import type {CommentBoxConfig} from '@github-ui/comment-box/CommentBox'
import type {Subject} from '@github-ui/comment-box/subject'
import styles from '@github-ui/commenting/AvatarStyles.module.css'
import {getQuotedText} from '@github-ui/commenting/quotes'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {userHovercardPath} from '@github-ui/paths'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {SafeHTMLString} from '@github-ui/safe-html'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import {Box, Link} from '@primer/react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {graphql, useRelayEnvironment} from 'react-relay'
import {fetchQuery, useFragment} from 'react-relay/hooks'
import type {OperationType} from 'relay-runtime'

import type {IssueBody$key} from './__generated__/IssueBody.graphql'
import type {IssueBodyContent$key} from './__generated__/IssueBodyContent.graphql'
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
}

const IssueBodySecondaryFragment = graphql`
  fragment IssueBodySecondaryFragment on Issue {
    viewerCanReport
    viewerCanReportToMaintainer
    viewerCanBlockFromOrg
    viewerCanUnblockFromOrg
  }
`

const REFRESH_TIMEOUT = 4 * 60 * 1000 // 4 minutes
const MOUSEOVER_DEBOUNCE = 10000 // 10 seconds

interface IssueBodyRefetchQueryResponse extends OperationType {
  variables: {
    id: string
  }
  response: {
    node: {
      bodyHTML: string
    }
  }
}

const IssueBodyRefetchQuery = graphql`
  query IssueBodyRefetchQuery($id: ID!) {
    node(id: $id) {
      ... on Issue {
        bodyHTML(unfurlReferences: true, renderTasklistBlocks: true)
      }
    }
  }
`

const IMAGE_VIDEO_TAG_REGEX = /<(?:video|img)/i

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
}: IssueBodyProps) {
  const data = useFragment(
    graphql`
      fragment IssueBody on Issue {
        id
        databaseId
        viewerDidAuthor
        locked
        # eslint-disable-next-line relay/unused-fields
        author {
          ...IssueBodyHeaderActions
          ...IssueBodyHeaderAuthor
          avatarUrl
          login
        }
        repository {
          databaseId
          nameWithOwner
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
  const [lastFetch, setLastFetch] = useState(() => new Date())

  const refresh_image_video_src = useFeatureFlag('refresh_image_video_src')

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

  // Handles refetching and setting the video / image src after the REFRESH_TIMEOUT has been met
  const mouseoverHandler = useCallback(async () => {
    // Check if we have an image / video and the FF is enabled
    if (!(refresh_image_video_src && IMAGE_VIDEO_TAG_REGEX.test(displayHtml))) return
    const now = new Date()

    // Check the timeout
    if (Math.abs(now.getTime() - lastFetch.getTime()) < REFRESH_TIMEOUT) return

    const result = await fetchQuery<IssueBodyRefetchQueryResponse>(relayEnvironment, IssueBodyRefetchQuery, {
      id: issueId,
    }).toPromise()
    const fetchedHtml = result?.node?.bodyHTML

    // Replace any video or image elements in the ref
    if (fetchedHtml) {
      const parser = new DOMParser()
      const currentDoc = issueBodyRef.current
      const fetchedDoc = parser.parseFromString(fetchedHtml, 'text/html')
      if (!currentDoc || !fetchedDoc) return

      const updateSrcAttributes = (tagName: string) => {
        const currentElements = currentDoc.getElementsByTagName(tagName)
        const fetchedElements = fetchedDoc.getElementsByTagName(tagName)

        for (let i = 0; i < currentElements.length; i++) {
          if (fetchedElements[i]) {
            ;(currentElements[i] as HTMLImageElement | HTMLVideoElement).src = (
              fetchedElements[i] as HTMLImageElement | HTMLVideoElement
            ).src
          }
        }
      }

      updateSrcAttributes('img')
      updateSrcAttributes('video')
      // Ensure the last fetch is updated
      setLastFetch(now)
    }
  }, [displayHtml, issueId, lastFetch, refresh_image_video_src, relayEnvironment])

  useEffect(() => {
    const element = issueBodyRef.current?.parentElement
    if (!element) return

    // Custom debounce logic as we can't leverage useDebounce
    // In this useEffect hook (that relies on the issueBodyRef to attach the mouseover event)
    let lastCallTime: number | null = null
    let isFirstCall = true

    const debouncedMouseoverHandler = () => {
      const now = Date.now()

      if (isFirstCall) {
        mouseoverHandler()
        isFirstCall = false
        lastCallTime = now
      } else if (lastCallTime === null || now - lastCallTime > MOUSEOVER_DEBOUNCE) {
        mouseoverHandler()
        lastCallTime = now
      }
    }

    // Add / tear down the event listener
    element.addEventListener('mouseover', debouncedMouseoverHandler)

    return () => {
      element.removeEventListener('mouseover', debouncedMouseoverHandler)
    }
  }, [mouseoverHandler])

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

  const {avatarUrl, login} = data.author ?? VALUES.ghost

  return (
    <Box
      sx={{
        display: 'flex',
        gap: 3,
      }}
    >
      <Link
        href={`/${login}`}
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
                    viewerCanBlockFromOrg: secondaryData?.viewerCanBlockFromOrg ?? false,
                    viewerCanUnblockFromOrg: secondaryData?.viewerCanUnblockFromOrg ?? false,
                    pendingBlock: data.pendingBlock ?? undefined,
                    pendingUnblock: data.pendingUnblock ?? undefined,
                  }}
                  secondaryKey={secondaryKey as IssueBodyHeaderSecondaryFragment$key}
                />

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
                  insideSidePanel={insideSidePanel}
                  repositoryId={data.repository.id}
                  onIssueEditStateChange={onIssueEditStateChange}
                />
              </>
            )}
          </Box>
        </Box>
      </Box>
    </Box>
  )
}
