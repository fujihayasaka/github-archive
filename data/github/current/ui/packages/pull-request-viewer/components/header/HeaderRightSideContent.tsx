import {Box, Button} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import type {HeaderRightSideContent_pullRequest$key} from './__generated__/HeaderRightSideContent_pullRequest.graphql'
import {ApplySuggestionsButton} from './ApplySuggestionsButton'

type HeaderRightSideContentProps = {
  hideSummaryInfo: boolean
  pullRequest: HeaderRightSideContent_pullRequest$key
  editTitleButtonRef: React.RefObject<HTMLButtonElement>
  onEdit: () => void
  viewOnly: boolean
  isSticky: boolean
  viewerLogin: string
}

export function HeaderRightSideContent({
  hideSummaryInfo,
  pullRequest,
  editTitleButtonRef,
  onEdit,
  viewOnly,
  isSticky,
}: HeaderRightSideContentProps) {
  const data = useFragment(
    graphql`
      fragment HeaderRightSideContent_pullRequest on PullRequest {
        state
      }
    `,
    pullRequest,
  )

  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: ['flex-end', 'flex-end', 'flex-end', 'flex-start'],
        gap: 2,
      }}
    >
      {!viewOnly && !isSticky && (
        <Button ref={editTitleButtonRef} sx={{ml: 1}} onClick={onEdit}>
          Edit
        </Button>
      )}
      {!hideSummaryInfo && data.state === 'OPEN' && (
        <>
          <ApplySuggestionsButton />
        </>
      )}
    </Box>
  )
}
