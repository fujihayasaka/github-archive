import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {IssueTemplateItem} from './IssueTemplateItem'
import {getTemplateUrl} from './utils/urls'
import type {IssueTemplateRow$key} from './__generated__/IssueTemplateRow.graphql'
import {IssueCreationKind} from './utils/model'

type IssueTemplateProps = {
  onTemplateSelected?: (filename: string, kind: IssueCreationKind) => void
  template: IssueTemplateRow$key
  nameWithOwner: string
}

export const IssueTemplateRow = ({nameWithOwner, template, onTemplateSelected}: IssueTemplateProps) => {
  const data = useFragment(
    graphql`
      fragment IssueTemplateRow on IssueTemplate {
        name
        about
        filename
      }
    `,
    template,
  )

  return (
    <IssueTemplateItem
      filename={data.filename}
      onTemplateSelected={filename => onTemplateSelected?.(filename, IssueCreationKind.IssueTemplate)}
      name={data.name}
      about={data.about}
      link={onTemplateSelected ? undefined : getTemplateUrl(nameWithOwner, data.filename)}
    />
  )
}
