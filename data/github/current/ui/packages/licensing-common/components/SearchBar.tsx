import {SearchIcon} from '@primer/octicons-react'
import {TextInput} from '@primer/react'
import styles from './SearchBar.module.css'

interface SearchBarProps {
  searchQuery: string
  setSearchQuery: (query: string) => void
  placeholder: string
  ariaLabel: string
}

export function SearchBar({searchQuery, setSearchQuery, placeholder, ariaLabel}: SearchBarProps) {
  return (
    <div className="mb-3 position-relative">
      <TextInput
        type="text"
        leadingVisual={SearchIcon}
        className={styles.searchInput}
        placeholder={placeholder}
        value={searchQuery}
        onChange={e => setSearchQuery(e.target.value)}
        aria-label={ariaLabel}
        data-testid="search-bar"
      />
    </div>
  )
}
