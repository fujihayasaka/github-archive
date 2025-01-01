import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {Pagination, UnderlineNav} from '@primer/react'
import {Link, useSearchParams} from 'react-router-dom'

import ExampleHeader from '../components/ExampleHeader'
import {IssueTable} from '../components/IssueTable'
import {reactCoreExamplesPaginationRoute} from './pagination-route'

export function ReactCoreExamplesPagination() {
  const {
    data: {count},
  } = useRouteQuery(reactCoreExamplesPaginationRoute, 'mainQuery')
  const {
    data: deferredIssues,
    isPending: isPendingIssues,
    isError: isIssuesError,
    refetch: refetchIssues,
  } = useRouteQuery(reactCoreExamplesPaginationRoute, 'deferredIssues')
  const issues = deferredIssues?.issues || []
  const [search] = useSearchParams()
  const page = search.get('page') || '1'

  const pageSize = 10
  const pageCount = Math.ceil(count / pageSize)

  return (
    <>
      <ExampleHeader
        pageTitle="Pagination"
        docsUrl="https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router/recipes/pagination.md"
      />
      <div data-testid="issues-nav">
        <UnderlineNav aria-label="Issues">
          <UnderlineNav.Item
            as={Link}
            to={reactCoreExamplesPaginationRoute.generatePath({})}
            aria-current
            counter={count}
          >
            Open Issues
          </UnderlineNav.Item>
        </UnderlineNav>
      </div>
      <IssueTable issues={issues} isPending={isPendingIssues} isError={isIssuesError} onRetry={() => refetchIssues()} />

      <Pagination
        pageCount={pageCount}
        currentPage={Number(page)}
        renderPage={({key, ...props}) => {
          if (props['aria-disabled']) {
            return <span key={key} {...props} />
          }

          return (
            <Link
              key={key}
              role="link"
              to={reactCoreExamplesPaginationRoute.generatePath(
                {},
                {
                  search: {
                    ...Object.fromEntries(search.entries()),
                    page: props.number.toString(),
                  },
                },
              )}
              {...props}
            />
          )
        }}
        data-testid="pagination"
      />
    </>
  )
}
