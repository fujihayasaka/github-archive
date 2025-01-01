/* eslint eslint-comments/no-use: off */
import {Box, Text} from '@primer/react'
import type {FC} from 'react'

import type {InboxListRow_v1_fragment$data} from './__generated__/InboxListRow_v1_fragment.graphql'
import Avatar from './InboxAvatar'

import styles from './InboxRowContent.module.css'

type InboxContentProps = {
  thread: InboxListRow_v1_fragment$data
  isMuted?: boolean
}

// Render the row subtitle: avatar of the user who triggered the notification and the notification body truncated
const InboxContent: FC<InboxContentProps> = ({thread, isMuted}) => {
  const {summaryItemAuthor, summaryItemBody} = thread
  return (
    <Box sx={{display: 'flex', flexDirection: 'row'}}>
      {summaryItemAuthor?.avatarUrl && (
        <Avatar
          key={summaryItemAuthor.avatarUrl}
          src={summaryItemAuthor.avatarUrl}
          className={isMuted ? styles.Avatar : undefined}
        />
      )}
      <Text
        sx={{
          fontWeight: 'normal',
          color: 'fg.muted',
          fontSize: '12px',
          textOverflow: 'ellipsis',
          overflow: 'hidden',
          whiteSpace: 'nowrap',
          mr: 4,
        }}
      >
        {summaryItemBody}
      </Text>
    </Box>
  )
}

const InboxRowCompactContent: FC<InboxContentProps> = ({thread, isMuted}) => {
  const {summaryItemAuthor, summaryItemBody} = thread
  const itemBody = summaryItemBody || ''

  return (
    <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'center'}}>
      {summaryItemAuthor?.avatarUrl && (
        <Avatar
          key={summaryItemAuthor.avatarUrl}
          src={summaryItemAuthor.avatarUrl}
          className={isMuted ? styles.AvatarCompact : undefined}
        />
      )}
      <Text
        sx={{
          fontWeight: 'normal',
          color: 'fg.muted',
          fontSize: '12px',
          textOverflow: 'ellipsis',
          overflow: 'hidden',
          whiteSpace: 'nowrap',
        }}
      >
        {itemBody}
      </Text>
    </Box>
  )
}

export default InboxContent
export {InboxRowCompactContent}
