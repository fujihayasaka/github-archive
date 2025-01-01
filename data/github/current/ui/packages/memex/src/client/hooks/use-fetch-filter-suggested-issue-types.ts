import {useCallback, useEffect, useState} from 'react'
import {fetchQuery, graphql, useRelayEnvironment} from 'react-relay'

import {getInitialState} from '../helpers/initial-state'
import type {useFetchFilterSuggestedIssueTypesQuery} from './__generated__/useFetchFilterSuggestedIssueTypesQuery.graphql'

type ProjectRequestVariables = {
  login: string
  number: number
}

const ProjectIssueTypesQuery = graphql`
  query useFetchFilterSuggestedIssueTypesQuery($login: String!, $number: Int!) {
    organization(login: $login) {
      projectV2(number: $number) {
        suggestedIssueTypeNames
      }
    }
  }
`

export const useFetchFilterSuggestedIssueTypes = (): {suggestedIssueTypeNames: ReadonlyArray<string> | undefined} => {
  const environment = useRelayEnvironment()
  const [suggestedIssueTypeNames, setSuggestedIssueTypeNames] = useState<ReadonlyArray<string> | undefined>(undefined)
  const {projectOwner, projectData} = getInitialState()

  const fetchFilterBarIssueTypeSuggestions = useCallback(
    async (login?: string, number?: number) => {
      try {
        if (environment && login && number) {
          const projectIssueTypes = await fetchQuery<useFetchFilterSuggestedIssueTypesQuery>(
            environment,
            ProjectIssueTypesQuery,
            {login, number} as ProjectRequestVariables,
            {fetchPolicy: 'store-or-network'},
          ).toPromise()

          setSuggestedIssueTypeNames(projectIssueTypes?.organization?.projectV2?.suggestedIssueTypeNames || [])
        }
      } catch {
        return []
      }
    },
    [environment],
  )

  useEffect(() => {
    void fetchFilterBarIssueTypeSuggestions(projectOwner?.login, projectData?.number)
  }, [fetchFilterBarIssueTypeSuggestions, projectOwner?.login, projectData?.number])

  return {suggestedIssueTypeNames}
}
