import {Filter, type FilterProps, type FilterQuery, type SubmitEvent} from '@github-ui/filter'
import type {Meta} from '@storybook/react'
import {useState} from 'react'
import type {OperationDescriptor} from 'relay-runtime'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {IssueTypeFilterProvider} from '../issue-type-filter-provider'
import {
  buildProjectIssuesTypes,
  buildRepositoryWithIssueTypes,
  buildViewerIssuesTypes,
} from './__tests__/utils/mock-data'
import styles from './IssueTypeFilterProvider.stories.module.css'

const setupRelayEnvironment = () => {
  const relayEnvironment = createMockEnvironment()
  relayEnvironment.mock.queueOperationResolver((operation: OperationDescriptor) =>
    MockPayloadGenerator.generate(operation, {
      User: () => buildViewerIssuesTypes(),
      Organization: () => buildProjectIssuesTypes(),
      Repository: () =>
        buildRepositoryWithIssueTypes({
          name: 'issues-react',
          owner: 'github',
        }),
    }),
  )

  return relayEnvironment
}

const meta = {
  title: 'Recipes/IssueTypeFilterProvider',
  component: Filter,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    settings: {
      control: {type: 'object'},
      table: {
        defaultValue: {summary: '{aliasMatching: false, groupAndKeywordSupport: true}'},
      },
    },
    onChange: {action: 'onChange'},
    onParse: {action: 'onParse'},
    onSubmit: {action: 'onSubmit'},
    onValidation: {action: 'onValidation'},
  },
  args: {
    id: 'storybook-filter',
    providers: [new IssueTypeFilterProvider({}, true, setupRelayEnvironment(), 'github/issues-react')],
    settings: {aliasMatching: false, groupAndKeywordSupport: true},
    label: 'Filter items',
    context: {repo: 'github/github'},
  },
} satisfies Meta<typeof Filter>

export default meta

const Items = ({query}: {query: string}) => {
  return (
    <div className={styles.Box_0}>
      {query ? (
        <div className={styles.Box_1}>
          <span className={styles.Text_0}>Filter the items using query</span>
          <span className={styles.Text_1}>{query}</span>
        </div>
      ) : (
        <span className={styles.Text_2}>Show a default list of items when no query is entered</span>
      )}
    </div>
  )
}

export const Playground = (props: FilterProps) => {
  const [filterValue, setFilterValue] = useState('')
  const [submittedValue, setSubmittedValue] = useState('')

  return (
    <div>
      <div className={styles.Box_2}>
        <Filter
          {...props}
          filterValue={filterValue}
          onChange={(value: string) => setFilterValue(value)}
          onSubmit={(request: FilterQuery, eventType: SubmitEvent) => {
            setSubmittedValue(request.raw)
            props.onSubmit?.(request, eventType)
          }}
        />
        <Items query={submittedValue} />
      </div>
    </div>
  )
}
