import {useState} from 'react'
import {Filter, type FilterProvider} from '@github-ui/filter'

import {AssigneeFilterProvider, AuthorFilterProvider, UserFilterProvider} from '@github-ui/filter/providers'

import styles from './Filter.module.css'

export default function ExampleFilter() {
  const [filterValue, setFilterValue] = useState('assignee:@me')
  return (
    <div className={styles.Box}>
      <Filter
        id="storybook-filter"
        label="Filter items"
        filterValue={filterValue}
        providers={defaultProviders}
        onChange={(value: string) => setFilterValue(value)}
      />
    </div>
  )
}

const defaultUserObject = {
  currentUserLogin: 'monalisa',
  currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/90914?v=4',
}

const defaultProviders: FilterProvider[] = [
  new AssigneeFilterProvider(defaultUserObject),
  new AuthorFilterProvider(defaultUserObject, {filterTypes: {multiKey: false}}),
  new UserFilterProvider(defaultUserObject),
]
