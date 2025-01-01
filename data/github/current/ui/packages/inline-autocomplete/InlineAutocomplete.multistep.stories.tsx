import {GitHubAvatar as Avatar} from '@github-ui/github-avatar'
import {ChevronRightIcon, GitPullRequestIcon, IssueOpenedIcon, MentionIcon, RepoIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps, FormControl, Textarea} from '@primer/react'
import type {Meta, StoryFn} from '@storybook/react'
import {useState} from 'react'

import {InlineAutocomplete} from './InlineAutocomplete'
import type {SelectSuggestionsEvent, ShowSuggestionsEvent, Suggestions, Trigger} from './types'
import {isNullSuggestion} from './utils'

export default {
  title: 'Recipes/InlineAutocomplete',
} as Meta

interface Extensions {
  login: string
  name: string
  avatar: string
}
const sampleExtensions: Extensions[] = [
  {login: 'monalisa', name: 'Monalisa Octocat', avatar: 'https://avatars.githubusercontent.com/github'},
  {login: 'primer', name: 'Primer', avatar: 'https://avatars.githubusercontent.com/primer'},
  {login: 'github', name: 'GitHub', avatar: 'https://avatars.githubusercontent.com/github'},
]
const filteredExtensions = (query: string) =>
  sampleExtensions
    .filter(
      extension =>
        extension.login.toLowerCase().includes(query.toLowerCase()) ||
        extension.name.toLowerCase().includes(query.toLowerCase()),
    )
    .slice(0, 5)
const ExtensionItem = ({extension, ...props}: {extension: Extensions} & ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <Avatar src={extension.avatar} />
    </ActionList.LeadingVisual>
    {extension.login}
  </ActionList.Item>
)

interface Issue {
  number: number
  title: string
  repo: string
}
const sampleIssues: Issue[] = [
  {number: 101, title: 'Resolve accessibility issues', repo: 'primer/react'},
  {number: 102, title: 'Update documentation for inline autocomplete', repo: 'primer/react'},
  {number: 103, title: 'Refactor code for better readability', repo: 'primer/react'},
  {number: 201, title: 'Fix broken links in README', repo: 'github/docs'},
  {number: 202, title: 'Add examples for API usage', repo: 'github/docs'},
  {number: 203, title: 'Improve search functionality', repo: 'github/docs'},
  {number: 301, title: 'Optimize image loading', repo: 'github/ui'},
  {number: 302, title: 'Add dark mode support', repo: 'github/ui'},
  {number: 303, title: 'Fix layout issues on mobile', repo: 'github/ui'},
]
const filteredIssues = (query: string, repository: string) =>
  sampleIssues
    .filter(
      issue =>
        issue.repo === repository &&
        (issue.title.toLowerCase().includes(query.toLowerCase()) || issue.number.toString().startsWith(query)),
    )
    .slice(0, 5)
const IssueItem = ({issue, ...props}: {issue: Issue} & ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <IssueOpenedIcon />
    </ActionList.LeadingVisual>
    {issue.title}{' '}
    <ActionList.Description>
      {issue.repo}#{issue.number}
    </ActionList.Description>
  </ActionList.Item>
)

interface PullRequest {
  number: number
  title: string
  repo: string
}
const samplePullRequests: PullRequest[] = [
  {number: 110, title: 'Fix bug in inline autocomplete', repo: 'primer/react'},
  {number: 210, title: 'Add new feature to inline autocomplete', repo: 'primer/react'},
  {number: 310, title: 'Improve performance of inline autocomplete', repo: 'primer/react'},
  {number: 101, title: 'Update README with examples', repo: 'github/docs'},
  {number: 102, title: 'Fix typos in documentation', repo: 'github/docs'},
  {number: 103, title: 'Add API usage guidelines', repo: 'github/docs'},
  {number: 201, title: 'Refactor UI components', repo: 'github/ui'},
  {number: 202, title: 'Add support for dark mode', repo: 'github/ui'},
  {number: 203, title: 'Fix layout issues on mobile', repo: 'github/ui'},
]
const filteredPullRequests = (query: string, repository: string) =>
  samplePullRequests
    .filter(
      pullRequest =>
        pullRequest.repo === repository &&
        (pullRequest.title.toLowerCase().includes(query.toLowerCase()) ||
          pullRequest.number.toString().startsWith(query)),
    )
    .slice(0, 5)
const PullRequestItem = ({pullRequest, ...props}: {pullRequest: PullRequest} & ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <GitPullRequestIcon />
    </ActionList.LeadingVisual>
    {pullRequest.title}{' '}
    <ActionList.Description>
      {pullRequest.repo}#{pullRequest.number}
    </ActionList.Description>
  </ActionList.Item>
)

interface Repository {
  name: string
}
const sampleRepositories: Repository[] = [{name: 'primer/react'}, {name: 'github/docs'}, {name: 'github/ui'}]
const filteredRepositories = (query: string) =>
  sampleRepositories.filter(repo => repo.name.toLowerCase().includes(query.toLowerCase())).slice(0, 5)
const RepositoryItem = ({repo, multistep, ...props}: {repo: Repository; multistep?: boolean} & ActionListItemProps) => (
  <ActionList.Item aria-haspopup={multistep} {...props}>
    <ActionList.LeadingVisual>
      <RepoIcon />
    </ActionList.LeadingVisual>
    {repo.name}
    {multistep && (
      <ActionList.TrailingVisual>
        <ChevronRightIcon />
      </ActionList.TrailingVisual>
    )}
  </ActionList.Item>
)

const categories = [
  {icon: MentionIcon, name: 'Extension', value: 'extension'},
  {icon: IssueOpenedIcon, name: 'Issue', value: 'repositoryForIssue'},
  {icon: GitPullRequestIcon, name: 'Pull Request', value: 'repositoryForPullRequest'},
  {icon: RepoIcon, name: 'Repository', value: 'repository'},
] as const
type Category = (typeof categories)[number]

const filteredCategories = (query: string) =>
  categories.filter(category => category.name.toLowerCase().includes(query.toLowerCase()))
const CategoryItem = ({category, ...props}: {category: Category} & ActionListItemProps) => {
  const Icon = category.icon
  return (
    <ActionList.Item aria-haspopup {...props}>
      <ActionList.LeadingVisual>{Icon ? <Icon /> : null}</ActionList.LeadingVisual>
      {category.name}
      <ActionList.TrailingVisual>
        <ChevronRightIcon />
      </ActionList.TrailingVisual>
    </ActionList.Item>
  )
}

const triggers: Trigger[] = [
  {
    triggerChar: '@',
    keepTriggerCharOnCommit: false,
    insertSpaceOnCommit: true,
    multiWord: true,
  },
]

type CategoryQuery =
  | {
      category: 'category' | 'extension' | 'repository' | 'repositoryForIssue' | 'repositoryForPullRequest'
      filter: string
    }
  | {
      category: 'issue' | 'pullRequest'
      filter: string
      repository: string
    }

const getFilteredSuggestions = (query: CategoryQuery): Suggestions => {
  switch (query.category) {
    case 'category':
      return filteredCategories(query.filter).map(categoryOption => ({
        value: null,
        key: categoryOption.value,
        render: props => <CategoryItem {...props} category={categoryOption} />,
      }))
    case 'extension':
      return filteredExtensions(query.filter).map(extension => ({
        value: `@${extension.login}`,
        render: props => <ExtensionItem {...props} extension={extension} />,
      }))
    case 'issue':
      return filteredIssues(query.filter, query.repository).map(issue => ({
        value: `${issue.repo}#${issue.number}`,
        render: props => <IssueItem {...props} issue={issue} />,
      }))
    case 'pullRequest':
      return filteredPullRequests(query.filter, query.repository).map(pr => ({
        value: `${pr.repo}#${pr.number}`,
        render: props => <PullRequestItem {...props} pullRequest={pr} />,
      }))
    case 'repository':
      return filteredRepositories(query.filter).map(repo => ({
        value: repo.name,
        render: props => <RepositoryItem {...props} repo={repo} />,
      }))
    case 'repositoryForIssue':
    case 'repositoryForPullRequest':
      return filteredRepositories(query.filter).map(repo => ({
        value: null,
        key: repo.name,
        render: props => <RepositoryItem {...props} repo={repo} multistep />,
      }))
  }
}

const getCategoryName = (category: CategoryQuery['category']) => {
  switch (category) {
    case 'extension':
      return 'Extensions'
    case 'repository':
      return 'Repositories'
    case 'repositoryForIssue':
    case 'issue':
      return 'Issues'
    case 'repositoryForPullRequest':
    case 'pullRequest':
      return 'Pull requests'
  }
}

export const Multistep: StoryFn = () => {
  const [query, setQuery] = useState<CategoryQuery>()

  const suggestions = query ? getFilteredSuggestions(query) : null

  const onShowSuggestions = (event: ShowSuggestionsEvent) =>
    setQuery(q => (q ? {...q, filter: event.query} : {category: 'category', filter: event.query}))

  const onHideSuggestions = () => setQuery(undefined)

  const onSelectSuggestion = ({suggestion}: SelectSuggestionsEvent) => {
    if (!isNullSuggestion(suggestion)) return

    switch (query?.category) {
      case 'category':
        setQuery({category: suggestion.key as Category['value'], filter: ''})
        break
      case 'repositoryForIssue':
        setQuery({category: 'issue', filter: '', repository: suggestion.key})
        break
      case 'repositoryForPullRequest':
        setQuery({category: 'pullRequest', filter: '', repository: suggestion.key})
        break
    }
  }

  const categoryName = query && getCategoryName(query.category)
  const title = categoryName ? `${categoryName} ›${'repository' in query ? ` ${query.repository} ›` : ''}` : undefined

  return (
    <FormControl>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show categories.</FormControl.Caption>
      <InlineAutocomplete
        triggers={triggers}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={onHideSuggestions}
        onSelectSuggestion={onSelectSuggestion}
        tabInsertsSuggestions
        title={title}
        asMenu
      >
        <Textarea />
      </InlineAutocomplete>
    </FormControl>
  )
}
