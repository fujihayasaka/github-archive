import activityHeaderStyles from '@github-ui/commenting/ActivityHeaderStyles.module.css'
import styles from '@github-ui/commenting/AvatarStyles.module.css'
import {SpammyBadge} from '@github-ui/commenting/SpammyBadge'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {MarkdownEditHistoryViewer} from '@github-ui/markdown-edit-history-viewer/MarkdownEditHistoryViewer'
import {MarkdownLastEditedBy} from '@github-ui/markdown-edit-history-viewer/MarkdownLastEditedBy'
import {userHovercardPath} from '@github-ui/paths'
import {Box, Label, Link, RelativeTime} from '@primer/react'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'

import {VALUES} from '../constants/values'
import type {IssueBodyHeader$key} from './__generated__/IssueBodyHeader.graphql'
import type {IssueBodyHeaderSecondaryFragment$key} from './__generated__/IssueBodyHeaderSecondaryFragment.graphql'
import {IssueBodyHeaderActions, type IssueBodyHeaderActionsProps} from './IssueBodyHeaderActions'
import {IssueBodyHeaderAuthor} from './IssueBodyHeaderAuthor'

export type IssueBodyHeaderProps = {
  additionalActions?: React.ReactNode
  comment: IssueBodyHeader$key
  url?: string
  isPullRequest?: boolean
  actionProps?: IssueBodyHeaderActionsProps
  secondaryKey?: IssueBodyHeaderSecondaryFragment$key
}

const IssueBodyHeaderSecondaryFragment = graphql`
  fragment IssueBodyHeaderSecondaryFragment on Comment {
    ...MarkdownEditHistoryViewer_comment
    ...MarkdownLastEditedBy
    showSpammyBadge
  }
`

export function IssueBodyHeader({
  additionalActions,
  comment,
  url,
  isPullRequest,
  actionProps,
  secondaryKey,
}: IssueBodyHeaderProps) {
  const data = useFragment(
    graphql`
      fragment IssueBodyHeader on Comment {
        ...IssueBodyHeaderActions_comment
        createdAt
        viewerDidAuthor
        author {
          ...IssueBodyHeaderAuthor
          ...IssueBodyHeaderActions
          avatarUrl
          login
        }
      }
    `,
    comment,
  )

  const createdAt = new Date(data.createdAt)
  const secondaryData = useFragment(IssueBodyHeaderSecondaryFragment, secondaryKey) ?? undefined

  const subText = (
    <>
      <span>{isPullRequest ? 'created ' : 'opened '}</span>
      {url ? (
        <Link href={url} sx={{color: 'fg.muted'}} data-testid="issue-body-header-link">
          <RelativeTime sx={{fontSize: 'inherit'}} date={createdAt}>
            on {createdAt.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}
          </RelativeTime>
        </Link>
      ) : (
        <RelativeTime sx={{fontSize: 'inherit'}} date={createdAt}>
          on {createdAt.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}
        </RelativeTime>
      )}
      <MarkdownLastEditedBy editInformation={secondaryData} includeSeparator />
      {/** As Pull Request Issue Body Descriptions show Author label to the right of created at date, we need to render this additional label */}
      {isPullRequest && <Label sx={{ml: 2}}>Author</Label>}
    </>
  )

  const {avatarUrl, login} = data.author ?? VALUES.ghost

  return (
    <Box
      sx={{
        backgroundColor: data.viewerDidAuthor ? 'accent.subtle' : 'canvas.subtle',
        borderTopLeftRadius: 2,
        borderTopRightRadius: 2,
        borderBottom: '1px solid',
        borderBottomColor: data.viewerDidAuthor ? 'accent.muted' : 'border.muted',
        color: 'fg.muted',
        display: 'flex',
        flexDirection: 'row',
        flex: 1,
        fontSize: 1,
        py: 1,
        pr: 1,
        pl: 3,
        flexWrap: 'wrap',
        justifyContent: 'space-between',
        alignItems: 'center',
        overflow: 'hidden',
      }}
    >
      <Box
        className={activityHeaderStyles.activityHeader}
        sx={{
          width: '100%',
          minWidth: 0,
          minHeight: 'var(--control-small-size, 28px)',
          justifyContent: 'space-between',
          alignItems: 'stretch',
          paddingBottom: 0,
        }}
      >
        <Box
          sx={{
            placeSelf: 'center',
            gridArea: 'avatar',
            marginRight: 2,
            display: isPullRequest ? ['flex', 'flex', 'none', 'none'] : '',
          }}
          className={styles.avatarInner}
        >
          <Link
            href={`/${login}`}
            data-hovercard-url={userHovercardPath({owner: login})}
            aria-label={`@${login}'s profile`}
            className={styles.avatarLink}
          >
            <GitHubAvatar size={24} src={avatarUrl} alt={`@${login}`} />
          </Link>
        </Box>

        <Box
          className={activityHeaderStyles.narrowViewportWrapper}
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
            <IssueBodyHeaderAuthor author={data.author || null} />
          </Box>
          <Box
            className={activityHeaderStyles.footer}
            sx={{
              gridArea: 'footer',
              lineHeight: '1.4',
            }}
          >
            {subText}
          </Box>
        </Box>

        <Box
          className={activityHeaderStyles.narrowViewportWrapper}
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
          <Box
            className={activityHeaderStyles.edits}
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
            <MarkdownEditHistoryViewer editHistory={secondaryData} />
          </Box>
          <Box
            sx={{
              gridColumnStart: 'badges',
              gridColumnEnd: 'actions',
              display: 'flex',
              columnGap: 'var(--base-size-4, 4px)',
              alignItems: 'center',
              justifyContent: 'flex-end',
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
              {secondaryData?.showSpammyBadge && <SpammyBadge />}
            </Box>
            <Box
              sx={{
                gridArea: 'actions',
                display: 'flex',
                columnGap: 'var(--base-size-4, 4px)',
              }}
            >
              {additionalActions}
              {actionProps && data.author && (
                <IssueBodyHeaderActions
                  url={actionProps.url}
                  comment={data}
                  issueBodyRef={actionProps.issueBodyRef}
                  onReplySelect={actionProps.onReplySelect}
                  startIssueBodyEdit={actionProps.startIssueBodyEdit}
                  viewerCanUpdate={actionProps.viewerCanUpdate}
                  viewerCanReport={actionProps.viewerCanReport}
                  viewerCanReportToMaintainer={actionProps.viewerCanReportToMaintainer}
                  viewerCanBlockFromOrg={actionProps.viewerCanBlockFromOrg}
                  viewerCanUnblockFromOrg={actionProps.viewerCanUnblockFromOrg}
                  issueId={actionProps.issueId}
                  owner={actionProps.owner}
                  ownerId={actionProps.ownerId}
                  ownerUrl={actionProps.ownerUrl}
                  author={data.author}
                  pendingBlock={actionProps.pendingBlock}
                  pendingUnblock={actionProps.pendingUnblock}
                />
              )}
            </Box>
          </Box>
        </Box>
      </Box>
    </Box>
  )
}
