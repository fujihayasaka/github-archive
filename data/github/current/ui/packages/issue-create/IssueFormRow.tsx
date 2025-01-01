import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {IssueTemplateItem} from './IssueTemplateItem'
import {getTemplateUrl} from './utils/urls'
import type {IssueFormRow$key} from './__generated__/IssueFormRow.graphql'
import {IssueCreationKind} from './utils/model'

type IssueFormRowProps = {
  onTemplateSelected?: (filename: string, kind: IssueCreationKind) => void
  form: IssueFormRow$key
  nameWithOwner: string
}

export const IssueFormRow = ({nameWithOwner, form, onTemplateSelected}: IssueFormRowProps) => {
  const data = useFragment(
    graphql`
      fragment IssueFormRow on IssueForm {
        name
        description
        filename
      }
    `,
    form,
  )

  return (
    <IssueTemplateItem
      filename={data.filename}
      onTemplateSelected={filename => onTemplateSelected?.(filename, IssueCreationKind.IssueForm)}
      name={data.name}
      about={data.description}
      link={onTemplateSelected ? undefined : getTemplateUrl(nameWithOwner, data.filename)}
    />
  )
}
