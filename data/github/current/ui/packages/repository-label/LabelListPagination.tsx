import {Pagination} from '@primer/react'
import {useCallback} from 'react'
import {CONSTS} from './constants/values'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {ssrSafeWindow} from '@github-ui/ssr-utils'

export const LabelListPagination = ({dataCount}: {dataCount: number}) => {
  const PAGE_SIZE = CONSTS.labelsPageSize
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()

  const currentPage = searchParams.get('page') ? parseInt(searchParams.get('page') as string, 10) : 1

  const handlePageChange = useCallback(
    (e: React.MouseEvent, page_number: number) => {
      e.preventDefault()
      if (page_number === currentPage) return
      const params = new URLSearchParams(searchParams)
      params.set('page', page_number.toString())

      const href = `${ssrSafeWindow?.location.pathname}?${params.toString()}`
      navigate(href)
    },
    [navigate, searchParams, currentPage],
  )
  const hrefBuilder = useCallback(
    (page_number: number) => {
      const params = new URLSearchParams(searchParams)
      params.set('page', page_number.toString())
      return `${ssrSafeWindow?.location.pathname}?${params.toString()}`
    },
    [searchParams],
  )

  return (
    <Pagination
      pageCount={Math.ceil(dataCount / PAGE_SIZE)}
      hrefBuilder={hrefBuilder}
      currentPage={currentPage}
      onPageChange={handlePageChange}
    />
  )
}

export default LabelListPagination
