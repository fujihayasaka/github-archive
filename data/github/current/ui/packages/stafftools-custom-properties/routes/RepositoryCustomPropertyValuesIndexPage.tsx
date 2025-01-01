import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Link} from '@primer/react'
import {DataTable, Blankslate} from '@primer/react/experimental'
import {useParams} from 'react-router-dom'
import {orgCustomPropertyDefinitionStafftoolsDetailsPath} from '../paths'

export function RepositoryCustomPropertyValuesIndexPage() {
  const {properties} = useRoutePayload<{properties: Record<string, string>}>()

  const tableData = Object.entries(properties).map(([key, value]) => ({
    id: key,
    property: key,
    value,
  }))

  const {owner} = useParams()

  if (tableData.length === 0) {
    return (
      <Blankslate border>
        <Blankslate.Heading>No properties set in this repository</Blankslate.Heading>
      </Blankslate>
    )
  }

  return (
    <DataTable
      data={tableData}
      columns={[
        {
          header: 'Property',
          field: 'property',
          renderCell: ({property}) => (
            <Link href={orgCustomPropertyDefinitionStafftoolsDetailsPath({org: owner!, propertyName: property})}>
              {property}
            </Link>
          ),
        },
        {header: 'Value', field: 'value'},
      ]}
    />
  )
}
