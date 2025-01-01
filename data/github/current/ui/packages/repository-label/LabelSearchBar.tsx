import {SearchIcon, XCircleFillIcon} from '@primer/octicons-react'
import {FormControl, IconButton, TextInput} from '@primer/react'
import styles from './SearchBar.module.css'
import {LABELS} from './constants/labels'
import {useNavigate, useSearchParams} from 'react-router-dom'
import {useCallback, useState} from 'react'
import {ssrSafeWindow} from '@github-ui/ssr-utils'

export function SearchBar() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const query = searchParams.get('q')

  const [searchQuery, setSearchQuery] = useState(query || '')
  const handleSearch = useCallback(() => {
    const params = new URLSearchParams(searchParams)
    params.set('q', searchQuery)

    const href = `${ssrSafeWindow?.location.pathname}?${params.toString()}`
    navigate(href)
  }, [navigate, searchQuery, searchParams])

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.key === 'Enter') {
        e.preventDefault()
        handleSearch()
      }
    },
    [handleSearch],
  )

  const clearSearch = useCallback(() => {
    setSearchQuery('')
    // If the search query is empty, remove the 'q' parameter from the URL
    const params = new URLSearchParams(searchParams)
    params.delete('q')
    const href = `${ssrSafeWindow?.location.pathname}?${params.toString()}`
    navigate(href)
  }, [navigate, searchParams])

  return (
    <form
      role="search"
      aria-labelledby="search-input"
      className={styles.searchWrapper}
      onSubmit={e => e.preventDefault()}
    >
      <FormControl id="search-input" className={styles.searchInputWrapper}>
        <FormControl.Label htmlFor="search-input" visuallyHidden>
          {LABELS.searchAll}
        </FormControl.Label>
        <TextInput
          type="text"
          className={styles.searchInput}
          placeholder={LABELS.searchAll}
          value={searchQuery}
          onKeyDown={handleKeyDown}
          onChange={e => setSearchQuery(e.currentTarget.value)}
          trailingAction={
            searchQuery !== '' ? (
              <IconButton
                icon={XCircleFillIcon}
                onClick={clearSearch}
                aria-label={LABELS.clearSearch}
                variant="invisible"
              />
            ) : undefined
          }
        />
      </FormControl>
      <IconButton
        aria-label={LABELS.search}
        size="medium"
        icon={SearchIcon}
        variant="default"
        onClick={handleSearch}
        className={styles.searchBtn}
      />
    </form>
  )
}
