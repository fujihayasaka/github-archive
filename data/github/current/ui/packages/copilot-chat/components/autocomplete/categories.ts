import {
  CommentDiscussionIcon,
  FileIcon,
  GitPullRequestIcon,
  IssueOpenedIcon,
  RepoIcon,
  StackIcon,
} from '@primer/octicons-react'

export const categoryNames = {
  agents: 'Extensions',
  repositories: 'Repositories',
  files: 'Files and folders',
  issues: 'Issues',
  pulls: 'Pull requests',
  discussions: 'Discussions',
} as const

export const topLevelCategories = [
  {
    name: categoryNames.agents,
    icon: StackIcon,
    value: 'agents',
    // extensions can only be invoked as the first thing in the input
    where: 'start',
  },
  {
    name: categoryNames.repositories,
    icon: RepoIcon,
    value: 'repositories',
    where: 'anywhere',
  },
  {
    name: categoryNames.files,
    icon: FileIcon,
    value: 'repositories:files',
    where: 'anywhere',
  },
  {
    name: categoryNames.issues,
    icon: IssueOpenedIcon,
    value: 'repositories:issues',
    where: 'anywhere',
  },
  {
    name: categoryNames.pulls,
    icon: GitPullRequestIcon,
    value: 'repositories:pulls',
    where: 'anywhere',
  },
  {
    name: categoryNames.discussions,
    icon: CommentDiscussionIcon,
    value: 'repositories:discussions',
    where: 'anywhere',
  },
] as const

export type AutocompleteCategory = (typeof topLevelCategories)[number]

export type CategoryValue = AutocompleteCategory['value']
export const CategoryValue = {
  is: (str: string): str is CategoryValue => topLevelCategories.some(category => category.value === str),
}
