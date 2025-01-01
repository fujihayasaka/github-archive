import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {RepositoryAndIssuePicker} from './RepositoryAndIssuePicker'
import {CurrentRepository, TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import type {RepositoryPickerCurrentRepoQuery} from '@github-ui/item-picker/RepositoryPickerCurrentRepoQuery.graphql'
import PRELOAD_CURRENT_REPOSITORY_QUERY from '@github-ui/item-picker/RepositoryPickerCurrentRepoQuery.graphql'
import {useIssueFilteringQueryGraphQLQuery} from '@github-ui/item-picker/useIssueFiltering'
import type {useIssueFilteringQuery} from '@github-ui/item-picker/useIssueFilteringQuery.graphql'
import {buildRepository} from '../test-utils/RepositoryPickerHelpers'
import {buildIssue} from '../test-utils/IssuePickerHelpers'

const meta = {
  title: 'RepositoryAndIssuePicker',
  component: RepositoryAndIssuePicker,
} satisfies Meta<typeof RepositoryAndIssuePicker>

export default meta

type Queries = {
  topRepositories: RepositoryPickerTopRepositoriesQuery
  issuePickerSearchGraphQLQuery: useIssueFilteringQuery
  repositoryPickerCurrentRepoQuery: RepositoryPickerCurrentRepoQuery
  preloadCurrentRepositoryQuery: RepositoryPickerCurrentRepoQuery
  repositoryPickerCurrentRepoQueryB: RepositoryPickerCurrentRepoQuery
  preloadCurrentRepositoryQueryB: RepositoryPickerCurrentRepoQuery
}

export const PickerWithDefaultOrganizationExample = {
  decorators: [relayDecorator<typeof RepositoryAndIssuePicker, Queries>],
  args: {
    defaultRepositoryNameWithOwner: 'orgA/repoA',
    organization: 'orgA',
    anchorElement: props => <button {...props}>Click me</button>,
  },
  parameters: {
    actions: {argTypesRegex: '^on.*'},
    relay: {
      queries: {
        topRepositories: {
          type: 'preloaded',
          query: TopRepositories,
          variables: {topRepositoriesFirst: 5, hasIssuesEnabled: true, owner: null},
        },
        issuePickerSearchGraphQLQuery: {
          type: 'preloaded',
          query: useIssueFilteringQueryGraphQLQuery,
          variables: {
            commenters: `commenter:@me`,
            mentions: `mentions:@me`,
            assignee: `assignee:@me`,
            author: `author:@me`,
            other: `state:open`,
            resource: '',
            queryIsUrl: false,
          },
        },
        repositoryPickerCurrentRepoQuery: {
          type: 'preloaded',
          query: CurrentRepository,
          variables: {owner: 'orgA', name: 'repoA'},
        },
        preloadCurrentRepositoryQuery: {
          type: 'preloaded',
          query: PRELOAD_CURRENT_REPOSITORY_QUERY,
          variables: {owner: 'orgA', name: 'repoA', includeTemplates: false},
        },
        repositoryPickerCurrentRepoQueryB: {
          type: 'preloaded',
          query: CurrentRepository,
          variables: {owner: 'orgA', name: 'repoB'},
        },
        preloadCurrentRepositoryQueryB: {
          type: 'preloaded',
          query: PRELOAD_CURRENT_REPOSITORY_QUERY,
          variables: {owner: 'orgA', name: 'repoB', includeTemplates: false},
        },
      },
      mockResolvers: {
        Repository({args}) {
          if (!args?.name || !args?.owner) {
            return {}
          }
          return buildRepository({name: args.name as string, owner: args.owner as string})
        },
        RepositoryConnection() {
          return {
            edges: [
              {node: buildRepository({owner: 'orgA', name: 'repoA'})},
              {node: buildRepository({owner: 'orgA', name: 'repoB'})},
              {node: buildRepository({owner: 'orgB', name: 'repoC'})},
            ],
          }
        },
        Query() {
          return {
            commenters: {
              nodes: [buildIssue({title: 'issueA'})],
            },
            mentions: {
              nodes: [buildIssue({title: 'mentions'})],
            },
            assignee: {
              nodes: [buildIssue({title: 'assignee'})],
            },
            author: {
              nodes: [buildIssue({title: 'author'})],
            },
            other: {
              nodes: [buildIssue({title: 'open'})],
            },
          }
        },
      },
    },
  },
} satisfies RelayStoryObj<typeof RepositoryAndIssuePicker, Queries>
