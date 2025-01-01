import {useCallback, useMemo, useState} from 'react'
import {Box, Link, Spinner, Text, TextInput} from '@primer/react'
import {SearchIcon} from '@primer/octicons-react'
import pluralize from 'pluralize'
import {fuzzyFilter} from '@github-ui/fuzzy-score/fuzzy-filter'
import {RepositoryTypeIcon} from '@github-ui/security-campaigns-shared/components/RepositoryTypeIcon'
import type {AlertsSummaryResponse} from '../hooks/use-alerts-summary-query'
import {Blankslate} from '@primer/react/experimental'

export type RepositoriesPanelProps = {
  alertsSummary: AlertsSummaryResponse | undefined
  isSummaryPending: boolean
}

export function RepositoriesPanel({alertsSummary, isSummaryPending}: RepositoriesPanelProps) {
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

  if (isSummaryPending || alertsSummary === undefined) {
    return (
      <Box sx={{height: '100%'}}>
        <Blankslate>
          <Blankslate.Description>
            <Spinner size="small" />
            <Text sx={{fontWeight: 'bold', marginLeft: 2}}>Loading...</Text>
          </Blankslate.Description>
        </Blankslate>
      </Box>
    )
  }

  return (
    <Box sx={{height: '100%'}}>
      <Box sx={{padding: 2}}>
        <TextInput
          type="search"
          leadingVisual={SearchIcon}
          placeholder="Search selected repositories"
          value={filter}
          onChange={handleChange}
          sx={{width: '100%'}}
        />
      </Box>
      {filteredRepositories.length === 0 && (
        <Blankslate>
          <Blankslate.Description>
            <Text sx={{color: 'fg.muted', fontSize: 1, display: 'flex', textAlign: 'center'}}>
              We couldn&apos;t find any repositories matching &apos;{filter}&apos;
            </Text>
          </Blankslate.Description>
        </Blankslate>
      )}
      {filteredRepositories.length > 0 && (
        <Box as="ul" sx={{height: 'calc(100% - 50px)', overflowY: 'auto'}}>
          {filteredRepositories.map(alertSummary => (
            <Box
              key={`${alertSummary.repository.ownerLogin}/${alertSummary.repository.name}`}
              as="li"
              sx={{
                display: 'flex',
                justifyContent: 'space-between',
                gap: 2,
                padding: 2,
                lineHeight: '20px',
                marginX: 2,
                borderBottomColor: 'border.default',
                borderBottomWidth: 1,
                borderBottomStyle: 'solid',
              }}
            >
              <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'center', gap: 1}}>
                <RepositoryTypeIcon typeIcon={alertSummary.repository.typeIcon} size={16} />
                <Link href={alertSummary.repository.path} target="_blank">
                  <span>{alertSummary.repository.name}</span>
                </Link>
              </Box>
              <Text sx={{color: 'fg.muted'}}>
                {alertSummary.alertCount} {pluralize('alert', alertSummary.alertCount)}
              </Text>
            </Box>
          ))}
        </Box>
      )}
    </Box>
  )
}
