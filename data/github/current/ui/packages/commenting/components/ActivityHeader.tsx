import {GitHubAvatar} from '@github-ui/github-avatar'
import {userHovercardPath} from '@github-ui/paths'
import {DotFillIcon} from '@primer/octicons-react'
import {Box, Link, RelativeTime, type SxProp, Text} from '@primer/react'
import {Suspense} from 'react'

import {LABELS} from '../constants/labels'
import {TEST_IDS} from '../constants/test-ids'
import styles from './ActivityHeader.module.css'
import avatarStyles from './Avatar.module.css'
import {CommentAuthorAssociation} from './CommentAuthorAssociation'
import {CommentHeaderBadge} from './CommentHeaderBadge'
import {CommentSubjectAuthor} from './CommentSubjectAuthor'
import type {CommentAuthorAssociation as GraphQlCommentAuthorAssociation} from './issue-comment/__generated__/IssueCommentHeader.graphql'
import {SpammyBadge} from './SpammyBadge'
import {SponsorsBadge} from './SponsorsBadge'

type ActivityData = {
  authorAssociation: GraphQlCommentAuthorAssociation
  id: string
  createdAt: string
  isHidden: boolean
  minimizedReason: string | null | undefined
  pendingMinimizeReason?: string | null
  showSpammyBadge?: boolean
  repository: {
    id: string
    isPrivate: boolean
    name: string
    owner: {
      login: string
      url: string
    }
  }
  url: string
  createdViaEmail?: boolean
  authorToRepoOwnerSponsorship?: {
    createdAt: string
    isActive: boolean
  } | null
  state?: string
}

export type ActivityHeaderHeadingProps = {
  as: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
}

type ActivityHeaderProps = {
  actions?: JSX.Element
  additionalHeaderMessage?: JSX.Element
  lastEditedByMessage?: JSX.Element
  editHistoryComponent?: JSX.Element
  avatarUrl: string
  comment: ActivityData
  commentSubjectAuthorLogin?: string
  commentSubjectType?: string
  commentRef?: React.RefObject<HTMLDivElement>
  isMinimized: boolean
  commentAuthorLogin: string
  userAvatar?: JSX.Element
  viewerDidAuthor?: boolean
  isReply?: boolean
  commentAuthorType?: string
  headingProps?: ActivityHeaderHeadingProps
  id?: string
  forceInlineAvatar?: boolean
  containerStyle?: SxProp
  threadCommentCount?: number
  commentBody?: string
  isInDialogMode?: boolean
} & SxProp
/**
 * Abstraction of a comment header that can be used in different contexts.
 */
export function ActivityHeader({
  actions,
  comment,
  commentAuthorLogin,
  isMinimized = false,
  avatarUrl,
  lastEditedByMessage,
  editHistoryComponent,
  additionalHeaderMessage,
  sx,
  viewerDidAuthor = false,
  /* eslint eslint-comments/no-use: off */
  /* eslint-disable @eslint-react/no-unstable-default-props */
  userAvatar = (
    <DefaultAvatar
      avatarUrl={avatarUrl}
      login={commentAuthorLogin}
      isHidden={!!comment.pendingMinimizeReason || comment.isHidden}
    />
  ),
  /* eslint-enable @eslint-react/no-unstable-default-props */
  commentSubjectAuthorLogin,
  commentSubjectType,
  isReply = false, // eslint-disable-next-line @eslint-react/no-unstable-default-props
  headingProps: {as: HeadingElement, ...headingProps} = {
    as: 'h3',
  },
  commentAuthorType,
  id,
  forceInlineAvatar,
  containerStyle,
  threadCommentCount,
  commentBody,
  isInDialogMode = false,
}: ActivityHeaderProps) {
  const containerStyles =
    containerStyle || isReply
      ? {}
      : {
          backgroundColor: viewerDidAuthor ? 'accent.subtle' : 'canvas.subtle',
          borderTopLeftRadius: '6px',
          borderTopRightRadius: '6px',
          borderBottom: '1px solid',
          borderColor: viewerDidAuthor ? 'accent.muted' : 'border.default',
          borderBottomWidth: isMinimized ? 0 : 1,
          py: forceInlineAvatar ? [1, 1, 2, 2] : 1,
          pr: 1,
          pl: 3,
          ...sx,
        }
  const commentMinimizedReason = comment.pendingMinimizeReason ?? comment.minimizedReason
  const commentHidden = !!commentMinimizedReason || comment.isHidden
  const createdAt = new Date(comment.createdAt)
  const subText = (
    <>
      {additionalHeaderMessage && (
        <Text sx={{color: 'fg.muted', overflow: 'hidden', textOverflow: 'ellipsis'}}>{additionalHeaderMessage}</Text>
      )}
      <Text
        sx={{
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          color: 'fg.muted',
        }}
      >
        <Link href={comment.url} sx={{color: 'inherit'}}>
          <RelativeTime date={createdAt}>
            on {createdAt.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}
          </RelativeTime>
        </Link>
        {comment.createdViaEmail && <span>{` ${LABELS.sentViaEmail}`}</span>}
      </Text>
      {commentHidden && (
        <Text sx={{color: 'fg.muted'}}>
          {' '}
          &middot;{' '}
          {commentMinimizedReason ? (
            <span>
              {LABELS.hiddenCommentWithReason} {commentMinimizedReason.replace(/_/g, '-').toLowerCase()}
            </span>
          ) : (
            <span>{LABELS.hiddenComment}</span>
          )}
        </Text>
      )}
      {lastEditedByMessage && !commentHidden && <Suspense>{lastEditedByMessage}</Suspense>}
    </>
  )
  return (
    <Box
      id={id}
      sx={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        ...containerStyles,
      }}
      data-testid={TEST_IDS.commentHeader}
    >
      <Box
        className={styles.activityHeader}
        sx={{
          width: '100%',
          minWidth: 0,
          minHeight: 'var(--control-small-size, 28px)',
          justifyContent: 'space-between',
          alignItems: 'stretch',
          // isXSmall &&
          paddingBottom: !lastEditedByMessage && !forceInlineAvatar ? 'var(--base-size-6, 6px)' : 0, // if there is no edit history row and the avatar is not inline, offset the spacing
        }}
      >
        <HeadingElement {...headingProps} className="sr-only">
          {isInDialogMode ? (
            <>
              {commentAuthorLogin}. ${commentBody}. Written at{' '}
              <RelativeTime date={createdAt}>
                {createdAt.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}{' '}
              </RelativeTime>
              . Has ${threadCommentCount} replies. To view replies use <kbd>→</kbd>.
            </>
          ) : (
            <>
              {commentAuthorLogin} commented{' '}
              <RelativeTime date={createdAt}>
                on {createdAt.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}{' '}
              </RelativeTime>
            </>
          )}
        </HeadingElement>
        <Box
          className={forceInlineAvatar ? '' : avatarStyles.avatarInner}
          sx={{
            placeSelf: 'center',
            gridArea: 'avatar',
            display: forceInlineAvatar ? 'flex' : ['flex', 'flex', 'none', 'none'],
            marginRight: 2,
          }}
        >
          {userAvatar}
        </Box>
        <Box
          className={styles.narrowViewportWrapper}
          data-testid={TEST_IDS.commentHeaderLeftSideItems}
          sx={{
            minWidth: 0,
            gridColumnStart: 'title',
            gridColumnEnd: 'badges',
            flexWrap: 'wrap',
            alignItems: 'center',
            flexShrink: 1,
            flexBasis: 'auto',
            columnGap: '0.45ch',
            paddingTop: 1,
            paddingBottom: 1,
          }}
        >
          <Box
            sx={{
              gridArea: 'title',
              marginTop: 0,
              alignItems: 'center',
              display: 'flex',
              flexShrink: 1,
              flexBasis: 'auto',
              overflow: 'hidden',
            }}
          >
            <Link
              data-testid={TEST_IDS.avatarLink}
              href={`/${commentAuthorType === 'Bot' ? 'apps/' : ''}${commentAuthorLogin}`}
              data-hovercard-url={userHovercardPath({owner: commentAuthorLogin})}
              sx={{
                fontSize: 1,
                color: commentHidden ? 'fg.muted' : 'fg.default',
                fontWeight: 500,
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
                alignSelf: 'flex-end',
              }}
            >
              {commentAuthorLogin}
            </Link>
          </Box>
          <Box
            className={styles.footer}
            sx={{
              gridArea: 'footer',
              lineHeight: '1.4',
            }}
          >
            {subText}
          </Box>
        </Box>
        <Box
          data-testid={TEST_IDS.commentHeaderRightSideItems}
          className={styles.narrowViewportWrapper}
          sx={{
            whiteSpace: 'nowrap',
            gridArea: 'actions',
            columnGap: 'var(--base-size-4, 4px)',
            justifyContent: 'flex-end',
            flexShrink: 2,
            flexGrow: 1,
            alignItems: 'flex-start',
          }}
        >
          {editHistoryComponent && (
            <Box
              sx={{
                gridArea: 'edits',
                display: 'flex',
                justifyContent: 'flex-end',
                overflow: 'hidden',
                flexGrow: 1,
                alignItems: ['flex-start', 'center', 'center', 'center'],
                ml: 2,
              }}
            >
              {editHistoryComponent}
            </Box>
          )}
          <Box
            sx={{
              gridColumnStart: 'badges',
              gridColumnEnd: 'actions',
              display: 'flex',
              columnGap: 'var(--base-size-4, 4px)',
              alignItems: 'center',
              justifyContent: 'flex-end',
              minHeight: 'var(--base-size-28, 28px)',
            }}
          >
            <Box
              sx={{
                display: 'flex',
                justifyContent: 'flex-end',
                alignItems: 'center',
                columnGap: 'var(--base-size-8, 8px)',
                ml: 1,
              }}
            >
              {comment.state === 'PENDING' && (
                <CommentHeaderBadge
                  leadingElement={<DotFillIcon />}
                  label="Pending"
                  ariaLabel="This review comment is pending"
                  testId="pending-badge"
                  variant="attention"
                  sx={{mr: 1}}
                />
              )}
              {!commentHidden &&
                !isMinimized &&
                comment.authorToRepoOwnerSponsorship &&
                comment.authorToRepoOwnerSponsorship.isActive && (
                  <SponsorsBadge
                    createdAt={comment.authorToRepoOwnerSponsorship.createdAt}
                    owner={comment.repository.owner.login}
                    viewerDidAuthor={viewerDidAuthor}
                  />
                )}
              {!commentHidden && !isMinimized && comment.showSpammyBadge && <SpammyBadge />}
              {!comment.repository.isPrivate && !commentHidden && !isMinimized && (
                <CommentAuthorAssociation
                  association={comment.authorAssociation}
                  viewerDidAuthor={viewerDidAuthor}
                  org={comment.repository.owner.login}
                  repo={comment.repository.name}
                />
              )}
              {commentAuthorLogin === commentSubjectAuthorLogin && (
                <CommentSubjectAuthor viewerDidAuthor={viewerDidAuthor} subjectType={commentSubjectType} />
              )}
            </Box>
            <Box
              sx={{
                display: 'flex',
                columnGap: 'var(--base-size-4, 4px)',
              }}
            >
              {actions}
            </Box>
          </Box>
        </Box>
      </Box>
    </Box>
  )
}
function DefaultAvatar({avatarUrl, login, isHidden}: {avatarUrl: string; login: string; isHidden: boolean}) {
  return (
    <Link
      href={`/${login}`}
      className={avatarStyles.avatarLink}
      data-hovercard-url={userHovercardPath({owner: login})}
      aria-label={`@${login}'s profile`}
    >
      <GitHubAvatar
        src={avatarUrl}
        alt={`@${login}`}
        size={24}
        className={isHidden ? avatarStyles.hiddenActivityAvatar : avatarStyles.activityAvatar}
      />
    </Link>
  )
}
