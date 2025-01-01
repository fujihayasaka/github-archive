import type {Meta} from '@storybook/react'
import {RuleFilesList, type RuleFilesListProps} from '../RuleFilesList'
import {RuleCategory} from '../../types/rule-category'
import {RuleSeverity} from '../../types/rule-severity'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'
import {getRuleFiles} from '../../test-utils/mock-data'

const meta = {
  title: 'Apps/Code Quality/Rule Files List',
  component: RuleFilesList,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof RuleFilesList>

export default meta

const defaultArgs: Partial<RuleFilesListProps> = {
  owner: 'octodemo',
  repo: 'repo1',
  rule: {
    title: 'Expression has no effect',
    ruleId: 'rule-1',
    category: RuleCategory.Maintainability,
    severity: RuleSeverity.Warning,
    findingsCount: 40,
  },
  files: getRuleFiles(),
}

export const Default = {
  args: defaultArgs,
  render: (args: RuleFilesListProps) => (
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="Closed campaigns">
          <RuleFilesList {...args} />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>
  ),
}
