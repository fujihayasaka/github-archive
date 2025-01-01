import {LABELS} from './constants/labels'
import {IssueCreationKind, BLANK_ISSUE_ID} from './utils/model'
import {IssueTemplateItem} from './IssueTemplateItem'
import {getTemplateUrl} from './utils/urls'

type BlankIssueItemProps = {
  onTemplateSelected?: (filename: string, kind: IssueCreationKind) => void
  nameWithOwner: string
}

export const BlankIssueItem = ({nameWithOwner, onTemplateSelected}: BlankIssueItemProps): JSX.Element => {
  return (
    <IssueTemplateItem
      filename={BLANK_ISSUE_ID}
      onTemplateSelected={() => onTemplateSelected?.(BLANK_ISSUE_ID, IssueCreationKind.BlankIssue)}
      name={LABELS.blankIssueName}
      about={LABELS.blankIssueDescription}
      link={onTemplateSelected ? undefined : getTemplateUrl(nameWithOwner, BLANK_ISSUE_ID)}
    />
  )
}
