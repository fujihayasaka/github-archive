import {graphql, useFragment, useLazyLoadQuery} from 'react-relay'
import {TemplateList, type TemplateListSelectedProp, type TemplateListSharedProps} from './TemplateList'
import {InfoIcon} from '@primer/octicons-react'
import {LABELS} from './constants/labels'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import styles from './TemplateListPane.module.css'
import type {TemplateListPaneQuery} from './__generated__/TemplateListPaneQuery.graphql'
import type {TemplateListPane$key} from './__generated__/TemplateListPane.graphql'

const TemplateListPaneGraphQLQuery = graphql`
  query TemplateListPaneQuery($id: ID!) {
    node(id: $id) {
      ... on Repository {
        ...TemplateListPane
      }
    }
  }
`

export type TemplateListPaneInternalProps = {
  repository: TemplateListPane$key
} & TemplateListPaneSharedProps

type TemplateListPaneSharedProps = {
  /** Id to use on validation messages
   *
   * `TemplateListNewPane` might be used with a repository that has issues disabled or has no templates available.
   * When this is the case, a message is shown and rendered with the id passed in this property.
   *
   * Consumers can then use this id in conjuction with an `aria-describedby` to ensure their control is properly
   * described with the message and accessible.
   */
  descriptionId?: string
} & TemplateListSelectedProp &
  TemplateListSharedProps

type TemplateListPaneFromRepoProps = {
  repositoryId: string
} & TemplateListPaneSharedProps

export function TemplateListPaneFromRepo({repositoryId, ...props}: TemplateListPaneFromRepoProps) {
  const data = useLazyLoadQuery<TemplateListPaneQuery>(TemplateListPaneGraphQLQuery, {
    id: repositoryId,
  })
  if (!data.node) return null

  return <TemplateListInternal repository={data.node} {...props} />
}

export function TemplateListInternal({repository, descriptionId, ...props}: TemplateListPaneInternalProps) {
  const {optionConfig} = useIssueCreateConfigContext()
  const {insidePortal} = optionConfig
  const data = useFragment(
    graphql`
      fragment TemplateListPane on Repository {
        hasIssuesEnabled
        ...TemplateList
      }
    `,
    repository,
  )

  return (
    <div>
      {data.hasIssuesEnabled ? (
        <TemplateList
          repository={data}
          {...props}
          className={`${
            !insidePortal
              ? `border borderColor-muted rounded-2 overflow-hidden
                ${optionConfig.showRepositoryPicker ? 'pt-0 mt-0' : 'py-2 mt-2'}`
              : ``
          }`}
        />
      ) : (
        <div className={`${styles.disabledStateGap} d-flex flex-row flex-items-center m-3`}>
          <InfoIcon />
          <span id={descriptionId}>{LABELS.issuesDisabledForRepo}</span>
        </div>
      )}
    </div>
  )
}
