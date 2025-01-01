import {Button, Flash, FormControl, TextInput} from '@primer/react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {setupMockFilterProviders} from '../__tests__/utils/mock-providers'
import {Filter, type FilterProps, type FilterQuery} from '../Filter'
import {FilterRevert} from '../FilterRevert'
import {handlers} from '../mocks/handlers'
import type {SubmitEvent} from '../types'
import styles from './FilterExamples.stories.module.css'

const meta: Meta = {
  title: 'Recipes/Filter/Examples',
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
    providers: setupMockFilterProviders(),
    settings: {aliasMatching: false, groupAndKeywordSupport: true},
    label: 'Filter items',
    context: {repo: 'github/github'},
  },
}

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

export const Default = (props: FilterProps) => {
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

export const NoContext = (props: FilterProps) => {
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
        <Flash variant="default">
          Note: This example doesn&apos;t have any repository or organization context, so any filter providers that rely
          on API responses will default to valid
        </Flash>
        <Items query={submittedValue} />
      </div>
    </div>
  )
}

export const Compact = (props: FilterProps) => {
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
Compact.args = {...meta.args, filterButtonVariant: 'compact'}

export const WithRevert = (props: FilterProps) => {
  const startingValue = 'assignee:@me'
  const [filterValue, setFilterValue] = useState(startingValue)
  const [submittedValue, setSubmittedValue] = useState(startingValue)

  return (
    <div>
      <div className={styles.Box_2}>
        <div className={styles.Box_3}>
          <Filter
            {...props}
            filterValue={filterValue}
            onChange={(value: string) => setFilterValue(value)}
            onSubmit={(request: FilterQuery, eventType: SubmitEvent) => {
              setSubmittedValue(request.raw)
              props.onSubmit?.(request, eventType)
            }}
          />
          {submittedValue !== startingValue && (
            <div>
              <FilterRevert
                href="#"
                onClick={e => {
                  setFilterValue(startingValue)
                  setSubmittedValue(startingValue)
                  e.preventDefault()
                }}
                className={styles.FilterRevert_0}
              />
            </div>
          )}
        </div>

        <Items query={submittedValue} />
      </div>
    </div>
  )
}

export const ExternallyControlled = (props: FilterProps) => {
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
        <Button
          onClick={() => {
            setFilterValue('assignee:@me')
            setSubmittedValue('assignee:@me')
          }}
        >
          Set to `assignee:@me`
        </Button>
        <Items query={submittedValue} />
      </div>
    </div>
  )
}

export const ButtonVariant = (props: FilterProps) => {
  const [filterValue, setFilterValue] = useState('')
  const [submittedValue, setSubmittedValue] = useState('')

  return (
    <div>
      <div className={styles.Box_4}>
        <div className={styles.Box_5}>
          <span className={styles.Text_3}>Issues</span>
          <Filter
            {...props}
            filterValue={filterValue}
            onChange={(value: string) => setFilterValue(value)}
            onSubmit={(request: FilterQuery, eventType: SubmitEvent) => {
              setSubmittedValue(request.raw)
              props.onSubmit?.(request, eventType)
            }}
          />
        </div>
        <Items query={submittedValue} />
      </div>
    </div>
  )
}
ButtonVariant.args = {...meta.args, variant: 'button'}

export const InputVariant = (props: FilterProps) => {
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
InputVariant.args = {...meta.args, variant: 'input'}

export const NoOnSubmit = (props: FilterProps) => {
  const [filterValue, setFilterValue] = useState('')

  return (
    <div>
      <div className={styles.Box_2}>
        <Filter
          {...props}
          filterValue={filterValue}
          onChange={(value: string) => setFilterValue(value)}
          onSubmit={undefined}
        />
        <Items query={filterValue} />
      </div>
    </div>
  )
}

export const NoOnSubmitInputVariant = (props: FilterProps) => {
  const [filterValue, setFilterValue] = useState('')

  return (
    <div>
      <div className={styles.Box_2}>
        <Filter
          {...props}
          filterValue={filterValue}
          onChange={(value: string) => setFilterValue(value)}
          onSubmit={undefined}
        />
        <Items query={filterValue} />
      </div>
    </div>
  )
}
NoOnSubmitInputVariant.args = {...meta.args, variant: 'input'}

export const Form = (props: FilterProps) => {
  const [filterValue, setFilterValue] = useState('')
  const [nameValue, setNameValue] = useState('')

  return (
    <div>
      <form
        onSubmit={e => {
          e.preventDefault()
          alert(`Submit data:\nName: ${nameValue}\nFilter: ${filterValue}`)
        }}
        className={styles.Box_6}
      >
        <div className={styles.Box_7}>
          <h1 className={styles.Text_4}>Create a saved view</h1>
          <div>
            <FormControl>
              <FormControl.Label>Name</FormControl.Label>
              <TextInput
                block
                placeholder="Your view name"
                value={nameValue}
                onChange={e => setNameValue(e.target.value)}
              />
            </FormControl>
          </div>
          <div className={styles.Box_3}>
            <label htmlFor="storybook-filter">Filter</label>
            <Filter
              {...props}
              placeholder="Filter"
              filterValue={filterValue}
              onSubmit={undefined}
              filterButtonVariant="compact"
              onChange={(value: string) => setFilterValue(value)}
            />
          </div>
        </div>
        <div className={styles.Box_8}>
          <Button>Cancel</Button>
          <Button type="submit" variant="primary">
            Create
          </Button>
        </div>
      </form>
    </div>
  )
}
