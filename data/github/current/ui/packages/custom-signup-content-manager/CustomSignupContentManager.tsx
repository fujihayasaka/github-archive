import {DataTable, Table} from '@primer/react/experimental'
import type {UniqueRow} from '@primer/react/experimental'
import type {CustomSignupContentPage} from './types'

export interface CustomSignupContentManagerProps {
  pageTitle: string
  pages: CustomSignupContentPage[]
}

export function CustomSignupContentManager({pageTitle, pages}: CustomSignupContentManagerProps) {
  // Each of DataTable's row must have a unique ID: use url_param as the ID.
  type CustomSignupContentPageRow = CustomSignupContentPage & UniqueRow
  const pagesWithId: CustomSignupContentPageRow[] = pages.map(page => ({...page, id: page.url_param}))

  return (
    <>
      <Table.Container>
        <Table.Title as="h2" id="custom-signup-content-manager-title">
          {pageTitle}
        </Table.Title>
        <DataTable
          aria-labelledby="custom-signup-content-manager-title"
          data={pagesWithId}
          columns={[
            {
              header: 'URL Parameter',
              field: 'url_param',
              rowHeader: true,
            },
            {
              header: 'Title',
              field: 'title',
            },
            {
              header: 'Visibility',
              field: 'published',
              renderCell: row => {
                return row.published ? 'Public' : 'Private'
              },
            },
          ]}
        />
      </Table.Container>
    </>
  )
}
