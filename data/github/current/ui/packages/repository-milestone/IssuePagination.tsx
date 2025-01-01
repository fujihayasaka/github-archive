import {useCallback, useMemo} from 'react'
import {VALUES} from './constants/values'
import {Pagination} from '@primer/react'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {useIsPlatform} from '@github-ui/use-is-platform'
import {ssrSafeWindow} from '@github-ui/ssr-utils'

type IssuePaginationProps = {
  totalCount: number
}

export function IssuePagination({totalCount}: IssuePaginationProps) {
  const totalPages = useMemo(() => {
    return Math.ceil(totalCount / VALUES.issuesPageSize)
  }, [totalCount])
  const [searchParams] = useSearchParams()
  const isMac = useIsPlatform(['mac'])
  const navigate = useNavigate()
  const currentPage = searchParams.get('page') ? parseInt(searchParams.get('page') as string, 10) : 1

  const handlePageChange = useCallback(
    (e: React.MouseEvent, pageNumber: number) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      const isMetaKey = isMac ? e.metaKey : e.ctrlKey
      const href = ssrSafeWindow?.location.href
      if (isMetaKey || e.shiftKey || !href) {
        return
      }
      e.preventDefault()
      const currentUrl = new URL(href, ssrSafeWindow?.location.origin)
      currentUrl.searchParams.set('page', pageNumber.toString())
      const targetUrlString = currentUrl.pathname + currentUrl.search
      navigate(targetUrlString)
    },
    [isMac, navigate],
  )

  if (!currentPage || totalPages < 2) {
    return null
  }
  return (
    <Pagination
      pageCount={totalPages}
      currentPage={currentPage}
      onPageChange={handlePageChange}
      marginPageCount={2}
      surroundingPageCount={2}
    />
  )
}
