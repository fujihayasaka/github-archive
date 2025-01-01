import type {Icon} from '@primer/octicons-react'
import {
  CodeIcon,
  TypographyIcon,
  LogIcon,
  GitBranchIcon,
  GitPullRequestIcon,
  MarkGithubIcon,
} from '@primer/octicons-react'
import type {NodeType} from './app'

type ContentField = 'content'

type PipeTypeInfo = {
  icon: Icon
  label: string
  contentFields: ContentField[]
  color?: string
}

export const pipeTypesInfo: Record<NodeType, PipeTypeInfo> = {
  code: {
    icon: CodeIcon,
    label: 'Code',
    color: 'fgColor-accent',
    contentFields: ['content'],
  },
  text: {
    icon: TypographyIcon,
    label: 'Text',
    color: 'fgColor-success',
    contentFields: ['content'],
  },
  prompt: {
    icon: LogIcon,
    label: 'Prompt',
    color: 'fgColor-attention',
    contentFields: ['content'],
  },
  visualize: {
    icon: GitBranchIcon,
    label: 'Visualize',
    color: 'fgColor-done',
    contentFields: ['content'],
  },
  'github-graphql': {
    icon: MarkGithubIcon,
    label: 'GitHub GraphQL',
    color: 'fgColor-severe',
    contentFields: ['content'],
  },
  pipeline: {
    icon: GitPullRequestIcon,
    label: 'Pipeline',
    color: 'fgColor-default',
    contentFields: ['content'],
  },
}
