import {graphql} from 'relay-runtime'

import {useFragment, useRelayEnvironment} from 'react-relay'
import type {PinnedIssueIssue$key} from './__generated__/PinnedIssueIssue.graphql'
import {useCallback, useRef} from 'react'
import {ActionList, ActionMenu, Box, IconButton, Link, RelativeTime, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {CommentIcon, GrabberIcon, KebabHorizontalIcon, PinSlashIcon} from '@primer/octicons-react'
import {userHovercardPath} from '@github-ui/paths'
import {getIssueStateIcon} from '@github-ui/list-view-items-issues-prs/StateIcon'
import {commitUnpinIssueMutation} from '@github-ui/issue-viewer/commitUnpinIssueMutation'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {ERRORS} from '../../constants/errors'
import {MoveDialogTrigger} from '@github-ui/drag-and-drop'

type PinnedIssueProps = {
  issue: PinnedIssueIssue$key
}

export function PinnedIssue({issue}: PinnedIssueProps) {
  const data = useFragment(
    graphql`
      fragment PinnedIssueIssue on Issue {
        id
        title
        titleHTML
        url
        createdAt
        state
        stateReason(enableDuplicate: true)
        number
        author {
          login
          url
        }
        totalCommentsCount
        repository {
          viewerCanPinIssues
        }
      }
    `,
    issue,
  )

  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const unpin = useCallback(() => {
    if (!data) return

    commitUnpinIssueMutation({
      environment,
      input: {issueId: data.id},
      onCompleted: () => {},
      onError: () => {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: ERRORS.couldNotUnpinIssue,
        })
      },
    })
  }, [addToast, data, environment])

  const editButtonRef = useRef<HTMLButtonElement>(null)
  if (!data) return <></>

  const stateOrReason = data.state === 'CLOSED' && data.stateReason === 'NOT_PLANNED' ? 'NOT_PLANNED' : data.state
  const state = getIssueStateIcon(stateOrReason)
  const commentCount = data.totalCommentsCount ?? 0
  const createdAt = new Date(data.createdAt)

  const wrapStyles = {
    display: '-webkit-box',
    overflow: 'hidden',
    '-webkit-box-orient': 'vertical',
    '-webkit-line-clamp': '2',
    maxWidth: '100%', // Constrains the container width
    whiteSpace: 'normal', // Fallback for unsupported browsers
    wordBreak: 'break-word', // Ensures long words break correctly
  }

  return (
    <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'flex-start', gap: 2, py: 1}}>
      <Box sx={{display: 'flex', flexDirection: 'column', flexGrow: 1}}>
        <Box sx={{display: 'flex', gap: 2}}>
          <Link
            aria-label={`View ${data.title}`}
            className={'css-truncate'}
            sx={{fontWeight: 'bold', color: 'fg.default', flexGrow: 1, fontSize: 2, pt: 1, mb: 1, ...wrapStyles}}
            href={data.url}
            muted
          >
            <Octicon sx={{color: state.color, mr: 2, mb: '1px'}} icon={state.icon} aria-label={state.description} />
            <SafeHTMLText html={data.titleHTML as SafeHTMLString} />
          </Link>
          {data.repository.viewerCanPinIssues && (
            <ActionMenu anchorRef={editButtonRef}>
              <ActionMenu.Anchor>
                <IconButton
                  size="small"
                  sx={{color: 'fg.muted', flexShrink: 0, gridArea: 'overflow'}}
                  icon={KebabHorizontalIcon}
                  variant="invisible"
                  aria-label="Pinned issue options"
                />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay width="medium">
                <ActionList>
                  {data && (
                    <ActionList.Item onSelect={unpin} aria-label={`Unpin issue #${data.number}, ${data.title}`}>
                      <ActionList.LeadingVisual>
                        <Octicon icon={PinSlashIcon} />
                      </ActionList.LeadingVisual>
                      Unpin
                    </ActionList.Item>
                  )}
                  <MoveDialogTrigger Component={ActionListItemReorder} returnFocusRef={editButtonRef} />
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          )}
        </Box>
        <Box sx={{display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 2}}>
          <Text sx={{fontSize: 0, color: 'fg.muted'}}>
            #{data.number} &middot;{' '}
            {data.author && (
              <Link
                aria-label={`View ${data.author.login} profile`}
                href={data.author.url}
                data-hovercard-url={userHovercardPath({owner: data.author.login})}
                muted
              >
                {data.author.login}
              </Link>
            )}{' '}
            {/* Added whitespace:normal to prevent the cards becoming different sizes to accomodate the timestamp length */}
            <span>opened </span>
            <RelativeTime date={createdAt}>
              on {createdAt.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}
            </RelativeTime>
          </Text>
          {commentCount > 0 && (
            <Box sx={{display: 'flex', flexShrink: 0, gap: 1, alignItems: 'center', pr: 1}}>
              <Octicon icon={CommentIcon} sx={{color: 'fg.muted'}} aria-label={`${commentCount} comments`} />
              <Text sx={{fontSize: 0, color: 'fg.muted', whiteSpace: 'nowrap'}}>{commentCount}</Text>
            </Box>
          )}
        </Box>
      </Box>
    </Box>
  )
}

// onClick is set automatically by the MoveDialogTrigger component
function ActionListItemReorder({onClick}: {onClick?: () => void}) {
  return (
    <ActionList.Item onSelect={onClick}>
      <ActionList.LeadingVisual>
        <Octicon icon={GrabberIcon} />
      </ActionList.LeadingVisual>
      Advanced move...
    </ActionList.Item>
  )
}
