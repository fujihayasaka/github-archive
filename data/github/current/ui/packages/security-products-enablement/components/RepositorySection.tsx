import {useMemo, useState, useRef} from 'react'
import {Pagination, Link} from '@primer/react'
import {settingsOrgSecurityProductsRepositories} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import RepositoryTable from './RepositoryTable'
import SearchFilter from './SearchFilter'
import FailureBanner from './FailureBanner'
import type {
  ChangesInProgress,
  FailureCounts,
  MiniSecurityConfiguration,
  Repository,
} from '../security-products-enablement-types'
import {SelectedRepositoryContext} from '../contexts/SelectedRepositoryContext'
import {useAppContext} from '../contexts/AppContext'
import {useRepositoryContext} from '../contexts/RepositoryContext'
import LicenseSection from './LicenseSection'
import {useSearchParams} from 'react-router-dom'
import pickBy from 'lodash-es/pickBy'
import {removeSearchParams, updateUrl} from '@github-ui/history'
import {Blankslate} from '@primer/react/experimental'
import {AlertIcon} from '@primer/octicons-react'

interface RepositorySectionProps {
  setChangesInProgress: React.Dispatch<React.SetStateAction<ChangesInProgress>>
  configs: MiniSecurityConfiguration[]
  failureCounts?: FailureCounts
}

class QueryState {
  query: string
  page: number

  constructor(query = '', page = 1) {
    this.query = query
    this.page = page
  }

  toURLSearchParams = (): URLSearchParams => {
    const nonDefaultPage = this.page === 1 ? '' : this.page.toString()
    const withNoEmptyValues = pickBy({q: this.query, page: nonDefaultPage})
    return new URLSearchParams(withNoEmptyValues)
  }

  toString = (): string => {
    return this.toURLSearchParams().toString()
  }

  static restoreFromSearchParams = (searchParams: URLSearchParams): QueryState => {
    return new QueryState(searchParams.get('q') || '', parseInt(searchParams.get('page') || '1'))
  }

  persistToHistory = (): void => {
    // only persist the query string if there's something worth persisting
    // otherwise remove the query string by setting the path
    if (this.query !== '' || this.page !== 1) {
      updateUrl(`?${this}`)
    } else {
      removeSearchParams()
    }
  }
}

const DEFAULT_FAILURE_COUNTS = {}

const RepositorySection: React.FC<RepositorySectionProps> = ({
  setChangesInProgress,
  configs,
  failureCounts = DEFAULT_FAILURE_COUNTS,
}) => {
  const {
    customPropertySuggestions,
    renderContext,
    capabilities,
    organization,
    pageCount: initialPageCount,
  } = useAppContext()
  const {setRepositories, totalRepositoryCount, setTotalRepositoryCount} = useRepositoryContext()
  const tableRef = useRef<HTMLTableElement>(null)
  const [searchParams] = useSearchParams()
  const [queryState, setQueryState] = useState<QueryState>(() => QueryState.restoreFromSearchParams(searchParams))
  const [filterQuery, setFilterQuery] = useState<string>(queryState.query)
  const [isQueryLoading, setIsQueryLoading] = useState<boolean>(false)
  const [selectedReposCount, setSelectedReposCount] = useState<number>(0)
  const [selectedReposMap, setSelectedRepos] = useState<Record<number, Repository>>({})
  const [pageCount, setPageCount] = useState(initialPageCount)
  const [hideFailureCounts, setHideFailureCounts] = useState<boolean>(false)

  const selectedRepositoryContextValue = useMemo(
    () => ({selectedReposMap, setSelectedRepos, selectedReposCount, setSelectedReposCount}),
    [selectedReposCount, selectedReposMap],
  )

  const [flashBannerType, setFlashBannerType] = useState<string | null>(null)
  const failureCountsPresent = Object.keys(failureCounts).length > 0
  const showFailureBanner = failureCountsPresent && !hideFailureCounts

  const executeQuery = (query: string, page: number) => {
    const newQueryState = new QueryState(query, page)
    newQueryState.persistToHistory()
    setQueryState(newQueryState)
    setFilterQuery(query)
    setIsQueryLoading(true)

    const url = `${settingsOrgSecurityProductsRepositories({org: organization})}?${newQueryState}`
    fetchData(url)
  }

  const fetchData = async (url: string) => {
    const result = await verifiedFetchJSON(url, {method: 'GET'})

    if (result.ok) {
      const resultJson = await result.json()
      setRepositories(resultJson.repositories)
      setSelectedRepos({})
      setSelectedReposCount(0)
      setTotalRepositoryCount(resultJson.totalRepositoryCount)
      setPageCount(resultJson.pageCount)
    } else {
      setFlashBannerType('searchTimedout')
    }
    setIsQueryLoading(false)
  }

  const handlePageChange = (e: React.MouseEvent, newPage: number) => {
    e.preventDefault()

    if (queryState.page !== newPage) {
      executeQuery(queryState.query, newPage)
    }
    tableRef.current?.scrollIntoView({behavior: 'smooth', block: 'start'})
  }

  if (totalRepositoryCount === -1) {
    return (
      <Blankslate border>
        <Blankslate.Visual>
          <AlertIcon size="medium" />
        </Blankslate.Visual>

        <Blankslate.Heading>Failed to load repositories</Blankslate.Heading>
        <Blankslate.Description>
          An error occurred while loading repositories. <br />
          Please try again or{' '}
          <Link inline href="https://support.github.com/" target="_blank">
            contact GitHub Support
          </Link>{' '}
          if the error persists.
        </Blankslate.Description>
      </Blankslate>
    )
  } else {
    return (
      <>
        <div className="f3-light mt-4 mb-1" ref={tableRef}>
          Apply configurations
        </div>
        {capabilities.advancedSecurity.purchased && (
          <LicenseSection
            selectedReposMap={selectedReposMap}
            selectedReposCount={selectedReposCount}
            totalRepositoryCount={totalRepositoryCount}
            filterQuery={queryState.query}
          />
        )}
        {showFailureBanner && (
          <FailureBanner closeFn={setHideFailureCounts} failureCounts={failureCounts} updateQuery={executeQuery} />
        )}
        {renderContext !== 'user' && (
          <SearchFilter
            configurationNames={configs.map(config => config.name)}
            onSubmit={request => executeQuery(request.raw, 1)}
            onChange={query => setFilterQuery(query)}
            definitions={customPropertySuggestions}
            filterQuery={filterQuery}
          />
        )}
        <SelectedRepositoryContext.Provider value={selectedRepositoryContextValue}>
          <RepositoryTable
            setChangesInProgress={setChangesInProgress}
            configs={configs}
            filterQuery={queryState.query}
            flashBannerType={flashBannerType}
            pageCount={pageCount}
            totalRepositoryCount={totalRepositoryCount}
            isQueryLoading={isQueryLoading}
          />
        </SelectedRepositoryContext.Provider>
        {pageCount > 1 && (
          <Pagination
            data-testid="pagination"
            pageCount={pageCount}
            currentPage={queryState.page}
            onPageChange={handlePageChange}
            marginPageCount={2}
            surroundingPageCount={2}
          />
        )}
      </>
    )
  }
}

export default RepositorySection
