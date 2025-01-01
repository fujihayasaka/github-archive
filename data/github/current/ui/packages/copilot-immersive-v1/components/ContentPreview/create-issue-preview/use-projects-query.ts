import {ProjectPickerGraphqlQuery, ProjectPickerProjectFragment} from '@github-ui/item-picker/ProjectPicker'
import type {
  ProjectPickerProject$data,
  ProjectPickerProject$key,
} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import type {ProjectPickerQuery} from '@github-ui/item-picker/ProjectPickerQuery.graphql'
import {useQuery} from '@github-ui/react-query'
import {useRelayEnvironment} from 'react-relay'
import {fetchQuery, readInlineData} from 'relay-runtime'

export type Project = ProjectPickerProject$data

export function useProjectsQuery({owner, repo, projects}: {owner?: string; repo?: string; projects?: string[]}) {
  const environment = useRelayEnvironment()

  return useQuery({
    queryKey: ['copilot-immersive-projects', JSON.stringify(environment), owner, repo, projects],
    queryFn: async () => {
      if (!owner || !repo || !projects || !projects.length) return []

      const data = await fetchQuery<ProjectPickerQuery>(environment, ProjectPickerGraphqlQuery, {
        owner,
        repo,
        query: projects.join(','),
      }).toPromise()

      const repositoryProjects = (data?.repository?.projectsV2?.nodes ?? [])
        .filter(node => !!node)
        .map(node => {
          // eslint-disable-next-line no-restricted-syntax
          return readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, node)
        })

      const recentRepositoryProjects = (data?.repository?.recentProjects?.edges ?? [])
        .map(edge => edge?.node)
        .filter(node => !!node)
        .map(node => {
          // eslint-disable-next-line no-restricted-syntax
          return readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, node)
        })

      const ownerProjects = (data?.repository?.owner?.projectsV2?.edges ?? [])
        .map(edge => edge?.node)
        .filter(node => !!node)
        .map(node => {
          // eslint-disable-next-line no-restricted-syntax
          return readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, node)
        })

      const recentOwnerProjects = (data?.repository?.owner?.recentProjects?.edges ?? [])
        .map(edge => edge?.node)
        .filter(node => !!node)
        .map(node => {
          // eslint-disable-next-line no-restricted-syntax
          return readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, node)
        })

      const uniqProjects = [
        ...[...repositoryProjects, ...recentRepositoryProjects, ...ownerProjects, ...recentOwnerProjects]
          .reduce((acc, item) => {
            acc.set(item.id, item)
            return acc
          }, new Map<string, ProjectPickerProject$data>())
          .values(),
      ]

      const initProjectsLower = new Set(projects.map(p => p.toLowerCase()))
      return (
        uniqProjects
          .filter(item => item.closed === false)
          .filter(item => item.hasReachedItemsLimit === false)
          // Despite querying by specific names, the query still returns several irrelevant projects
          // This adds a case-insensitive comparison on title, which should be what the user is asking for.
          .filter(item => initProjectsLower.has(item.title.toLowerCase()))
      )
    },
  })
}
