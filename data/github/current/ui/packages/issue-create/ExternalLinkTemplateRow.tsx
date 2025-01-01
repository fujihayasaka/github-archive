import {LinkExternalIcon} from '@primer/octicons-react'
import {noop} from '@github-ui/noop'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {IssueTemplateItem} from './IssueTemplateItem'
import type {ExternalLinkTemplateRow$key} from './__generated__/ExternalLinkTemplateRow.graphql'

type ExternalLinkTemplateRowProps = {
  repositoryContactLink: ExternalLinkTemplateRow$key
}

export const ExternalLinkTemplateRow = ({repositoryContactLink}: ExternalLinkTemplateRowProps): JSX.Element => {
  const data = useFragment(
    graphql`
      fragment ExternalLinkTemplateRow on RepositoryContactLink {
        about
        url
        name
      }
    `,
    repositoryContactLink,
  )

  return (
    <IssueTemplateItem
      filename={data.name}
      onTemplateSelected={noop}
      name={data.name}
      link={data.url}
      about={data.about}
      externalLink
      trailingIcon={<LinkExternalIcon />}
    />
  )
}
