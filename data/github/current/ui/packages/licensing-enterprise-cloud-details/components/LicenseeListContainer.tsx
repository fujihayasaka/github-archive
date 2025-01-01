import {useQuery} from '@github-ui/react-query'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useEffect, useState} from 'react'
import {LicenseeList} from './LicenseeList'
import type {Licensee} from '../types/licensee'
import {visualStudioFilterOptions, type VisualStudioFilter} from '../types/visual-studio-filter-options'
import {useDebounce} from '@github-ui/use-debounce'
import {LicenseeFilterBar} from './LicenseeFilterBar'
import {VisualStudioMatchDialog} from './VisualStudioMatchDialog'
import {VisualStudioUnmatchDialog} from './VisualStudioUnmatchDialog'

const PER_PAGE = 15

export type LicenseesResponse = {
  licensees: Licensee[]
  totalPages: number
}

type LicenseeListContainerProps = {
  isVolumeLicensed: boolean
}

export function LicenseeListContainer(props: LicenseeListContainerProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [debouncedSearchQuery, setDebouncedSearchQuery] = useState('')
  const debouncedSetSearchQuery = useDebounce((value: string) => setDebouncedSearchQuery(value), 400)
  const [visualStudioFilter, setVisualStudioFilter] = useState<VisualStudioFilter>(
    visualStudioFilterOptions[0]?.value ?? 'all',
  )

  const [matchLicensee, setMatchLicensee] = useState<Licensee | null>(null)
  const [isMatching, setIsMatching] = useState(false)
  const [matchError, setMatchError] = useState<string | null>(null)
  async function handleMatchSave() {
    if (!matchLicensee) return
    setIsMatching(true)
    setMatchError(null)

    try {
      // TODO: Implement the actual save logic
      throw new Error('There was a problem saving the license change, please try again.')
    } catch (error) {
      setMatchError(error instanceof Error ? error.message : String(error))
    } finally {
      setIsMatching(false)
    }
  }

  const [unmatchLicensee, setUnmatchLicensee] = useState<Licensee | null>(null)
  const [isUnmatching, setIsUnmatching] = useState(false)
  const [unmatchError, setUnmatchError] = useState<string | null>(null)
  async function handleUnmatchSave() {
    if (!unmatchLicensee) return
    setIsUnmatching(true)
    setUnmatchError(null)

    try {
      // TODO: Implement the actual save logic
      throw new Error('There was a problem saving the license change, please try again.')
    } catch (error) {
      setUnmatchError(error instanceof Error ? error.message : String(error))
    } finally {
      setIsUnmatching(false)
    }
  }

  function closeDialogs() {
    setMatchLicensee(null)
    setMatchError(null)

    setUnmatchLicensee(null)
    setUnmatchError(null)
  }

  // Update debounced value when searchQuery changes
  useEffect(() => {
    debouncedSetSearchQuery(searchQuery)
  }, [searchQuery, debouncedSetSearchQuery])

  const [currentPage, setCurrentPage] = useState(1)
  const [totalPages, setTotalPages] = useState(0)
  const [currentPageLicensees, setCurrentPageLicensees] = useState<Licensee[]>([])

  // Reset current page when search or visualStudioFilter changes
  useEffect(() => {
    setCurrentPage(1)
  }, [debouncedSearchQuery, visualStudioFilter])

  const {basePath} = useNavigation()

  const {
    isError,
    isFetching,
    data: licenseesResponse,
  } = useQuery<LicenseesResponse>({
    retry: process.env.NODE_ENV === 'test' ? false : 3,
    refetchOnWindowFocus: true,
    queryKey: ['licensing', basePath, 'licensee-list', debouncedSearchQuery, visualStudioFilter, currentPage],
    queryFn: async () => {
      const url = new URL(`${basePath}/enterprise_licensing/ghec/licensees`, window.location.origin)
      const params = new URLSearchParams({
        search: debouncedSearchQuery,
        vs_filter: visualStudioFilter,
        page: currentPage.toString(),
        per_page: PER_PAGE.toString(),
      })
      url.search = params.toString()
      const resp = await verifiedFetchJSON(url.toString())
      if (!resp.ok) {
        throw new Error('Failed to fetch licensees')
      }
      return resp.json()
    },
  })

  useEffect(() => {
    if (licenseesResponse) {
      const {licensees, totalPages: newTotalPages} = licenseesResponse
      setCurrentPageLicensees(licensees)
      setTotalPages(newTotalPages)
      if (newTotalPages > 0 && currentPage > newTotalPages) {
        setCurrentPage(newTotalPages)
      }
    }
  }, [currentPage, licenseesResponse, totalPages])

  return (
    <>
      <LicenseeFilterBar
        searchQuery={searchQuery}
        setSearchQuery={setSearchQuery}
        visualStudioFilter={visualStudioFilter}
        setVisualStudioFilter={setVisualStudioFilter}
      />
      <LicenseeList
        licensees={currentPageLicensees}
        isError={isError}
        isFetching={isFetching}
        currentPage={currentPage}
        totalPages={totalPages}
        onPageChange={setCurrentPage}
        onOpenMatchDialog={setMatchLicensee}
        onOpenUnmatchDialog={setUnmatchLicensee}
      />
      {matchLicensee && (
        <VisualStudioMatchDialog
          errorMessage={matchError}
          hasVssLicensesLeft // TODO: Replace with actual check
          isSaving={isMatching}
          isVolumeLicensed={props.isVolumeLicensed}
          licenseeFullName={matchLicensee.fullName ?? matchLicensee.login}
          licenseeLogin={matchLicensee.login}
          onClose={closeDialogs}
          onConfirm={handleMatchSave}
          onDismissError={() => setMatchError(null)}
        />
      )}
      {unmatchLicensee && (
        <VisualStudioUnmatchDialog
          errorMessage={unmatchError}
          isSaving={isUnmatching}
          isVolumeLicensed={props.isVolumeLicensed}
          onClose={closeDialogs}
          onConfirm={handleUnmatchSave}
          onDismissError={() => setUnmatchError(null)}
        />
      )}
    </>
  )
}
