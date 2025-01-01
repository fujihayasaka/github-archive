import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {setupMockFilterProviders} from '../__tests__/utils/mock-providers'
import {Filter, type FilterProps, type FilterQuery} from '../Filter'
import {handlers} from '../mocks/handlers'
import type {SubmitEvent} from '../types'
import styles from './FilterDeprecated.stories.module.css'

const meta = {
  title: 'Recipes/Filter',
  component: Filter,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers,
    },
  },
  argTypes: {
    settings: {
      control: {type: 'object'},
      table: {
        defaultValue: {summary: '{aliasMatching: false}'},
      },
    },
    onChange: {action: 'onChange'},
    onParse: {action: 'onParse'},
    onSubmit: {action: 'onSubmit'},
    onValidation: {action: 'onValidation'},
  },
  args: {
    id: 'storybook-filter',
    providers: setupMockFilterProviders(),
    settings: {aliasMatching: false},
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

export const FilterExperimental = (props: FilterProps) => {
  const [filterValue, setFilterValue] = useState(
    'assignee:@me (state:open AND (is:issue OR is:pr)) AND (label:"🐛 bug" AND milestone:"invalid label")',
  )
  const [submittedValue, setSubmittedValue] = useState('')

  return (
    <div>
      <div className={styles.Box_2}>
        <Filter
          {...props}
          filterValue={filterValue}
          onChange={(value: string) => setFilterValue(value)}
          settings={props.settings}
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
