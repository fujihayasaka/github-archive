import {useCallback, useMemo, useState} from 'react'
import {Flash, Link, Spinner, TextInput} from '@primer/react'
import {SearchIcon} from '@primer/octicons-react'
import pluralize from 'pluralize'
import {RepositoryTypeIcon} from './RepositoryTypeIcon'
import {Blankslate} from '@primer/react/experimental'
import {repositoryPath} from '@github-ui/paths'
import {number as formatNumber} from '@github-ui/formatters'

import styles from './RepositoriesPanel.module.css'
import type {AlertsSummaryResponse} from '../hooks/use-alerts-summary-query'
import {fuzzyFilter} from '@github-ui/fuzzy-score/fuzzy-filter'

export type RepositoriesPanelProps = {
  alertsSummary: AlertsSummaryResponse | undefined
  isSummaryPending: boolean
  error: Error | null
}

export function RepositoriesPanel({alertsSummary, isSummaryPending, error}: RepositoriesPanelProps) {
  const [filter, setFilter] = useState('')

  const filteredRepositories = useMemo(() => {
    if (!alertsSummary) {
      return []
    }

    const normalizedFilter = filter.trim()
    if (!normalizedFilter) {
      return [...alertsSummary.repositories].sort((a, b) => a.repository.name.localeCompare(b.repository.name))
    }

    return fuzzyFilter({
      items: alertsSummary.repositories,
      filter: normalizedFilter,
      key: alertSummary => alertSummary.repository.name,
    })
  }, [filter, alertsSummary])

  const handleChange = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    setFilter(event.target.value)
  }, [])

  if (!error && (isSummaryPending || alertsSummary === undefined)) {
    return (
      <div className={styles.mainBox}>
        <Blankslate>
          <Blankslate.Description>
            <Spinner size="small" />
            <span className={styles.loadingScreenText}>Loading...</span>
          </Blankslate.Description>
        </Blankslate>
      </div>
    )
  }

  if (error) {
    return (
      <div className={styles.errorBox}>
        <Flash variant="danger">{error.message}</Flash>
      </div>
    )
  }

  return (
    <div className={styles.mainBox}>
      <div className={styles.searchBox}>
        <TextInput
          type="search"
          leadingVisual={SearchIcon}
          placeholder="Search selected repositories"
          value={filter}
          onChange={handleChange}
          aria-label={`Search selected repositories`}
          className={styles.textInput}
        />
      </div>
      {filteredRepositories.length === 0 && (
        <Blankslate>
          <Blankslate.Description>
            <span className={styles.searchInfoText}>
              We couldn&apos;t find any repositories matching &apos;{filter}&apos;
            </span>
          </Blankslate.Description>
        </Blankslate>
      )}
      {filteredRepositories.length > 0 && (
        <ul className={styles.filteredRepositoriesBox}>
          {filteredRepositories.map(alertSummary => (
            <li
              key={`${alertSummary.repository.ownerLogin}/${alertSummary.repository.name}`}
              className={styles.repositoriesListItemBox}
            >
              <div className={styles.repositoriesLinkBox}>
                <RepositoryTypeIcon typeIcon={alertSummary.repository.typeIcon} size={16} />
                <Link
                  href={repositoryPath({owner: alertSummary.repository.ownerLogin, repo: alertSummary.repository.name})}
                  target="_blank"
                >
                  <span>{alertSummary.repository.name}</span>
                </Link>
              </div>
              <span className={styles.filteredRepositoriesText}>
                {formatNumber(alertSummary.alertCount)} {pluralize('alert', alertSummary.alertCount)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
