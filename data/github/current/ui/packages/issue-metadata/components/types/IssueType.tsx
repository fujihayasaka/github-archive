import {Box} from '@primer/react'
import {IssueTypeToken} from '@github-ui/issue-type-token'

import type {IssueTypePickerIssueType$data} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import {TEST_IDS} from '../../constants/test-ids'

type IssueTypeProps = {
  type?: IssueTypePickerIssueType$data | null
  repoNameWithOwner?: string
  anchorProps?: React.HTMLAttributes<HTMLElement>
}

export function IssueType({type, anchorProps, repoNameWithOwner}: IssueTypeProps) {
  return (
    <>
      {type ? (
        <div data-testid={TEST_IDS.typeContainer}>
          <IssueTypeToken
            name={type.name}
            color={type.color}
            href={`/${repoNameWithOwner}/issues?q=type:"${type.name}"`}
            getTooltipText={(isTruncated: boolean) => (isTruncated ? type.name : undefined)}
            sx={{mb: 2}}
          />
        </div>
      ) : (
        <Box sx={{height: '0px', p: 0, m: 0, border: '0', visibility: 'hidden'}} {...anchorProps} />
      )}
    </>
  )
}
