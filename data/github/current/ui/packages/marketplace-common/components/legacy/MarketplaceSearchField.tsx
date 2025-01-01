import {SearchIcon} from '@primer/octicons-react'
import {Spinner, TextInput} from '@primer/react'
import styles from '../marketplace-search-field.module.css'
import {useFilterContext} from '../../contexts/FilterContext'
import {useCallback, useState} from 'react'
import {debounce} from '@github/mini-throttle'
import {useSearchType} from '../../contexts/SearchTypeContext'

export default function MarketplaceSearchField() {
  const {query, legacyOnQueryChange: onQueryChange, loading} = useFilterContext()
  const {type} = useSearchType()
  const [privateQuery, setPrivateQuery] = useState<string>(query)

  // eslint-disable-next-line react-compiler/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const debouncedSetQuery = useCallback(
    debounce((newQuery: string) => {
      onQueryChange(newQuery)
    }, 400),
    [onQueryChange],
  )

  const handleQueryChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setPrivateQuery(event.target.value)
      debouncedSetQuery(event.target.value)
    },
    [debouncedSetQuery],
  )

  const handleSubmit = useCallback(
    (event: React.FormEvent) => {
      event.preventDefault()
      const search = new URLSearchParams()
      search.set('query', privateQuery)
      if (type) search.set('type', type)
      location.replace(`/marketplace?${search.toString()}`)
    },
    [privateQuery, type],
  )

  return (
    <form onSubmit={handleSubmit}>
      <TextInput
        block
        size="large"
        leadingVisual={
          loading ? (
            <div className="d-flex">
              <Spinner size="small" />
            </div>
          ) : (
            SearchIcon
          )
        }
        aria-label="Search Marketplace"
        placeholder={'Search for Copilot extensions, apps, actions, and models'}
        className={`width-full ${styles['search-input']}`}
        value={privateQuery}
        onChange={handleQueryChange}
        data-testid="search-input"
      />
    </form>
  )
}
