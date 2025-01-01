import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {DataTable, Blankslate} from '@primer/react/experimental'
import type {CustomPropertyDefinitionSummaryPayload} from '../types/stafftools-custom-properties-types'
import {CheckIcon, XIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {usePropertySource} from '../hooks/use-property-source'
import styles from './DefinitionsIndexPage.module.css'
import {businessCustomPropertyDefinitionStafftoolsListPath} from '../paths'

export function DefinitionsIndexPage() {
  const {definitions} = useRoutePayload<CustomPropertyDefinitionSummaryPayload>()
  const {sourceType, detailsPathFromPropertyName} = usePropertySource()

  const tableData = definitions.map(definition => ({
    ...definition,
    id: definition.name,
  }))

  if (tableData.length === 0) {
    return (
      <Blankslate border>
        <Blankslate.Heading>No definitions set in this {sourceType}</Blankslate.Heading>
      </Blankslate>
    )
  }

  return (
    <DataTable
      data={tableData}
      columns={[
        {
          header: 'Name',
          field: 'name',
          renderCell: ({name, managedBySlug}) => (
            <PropertyNameCell
              name={name}
              detailsPath={detailsPathFromPropertyName(name)}
              managedBySlug={managedBySlug}
            />
          ),
        },
        {
          header: 'Required',
          field: 'required',
          renderCell: ({required}) => <Octicon icon={required ? CheckIcon : XIcon} />,
        },
        {header: 'Default value', field: 'defaultValue'},
      ]}
    />
  )
}

function PropertyNameCell({
  name,
  detailsPath,
  managedBySlug,
}: {
  name: string
  detailsPath: string
  managedBySlug: string | null
}) {
  return (
    <>
      <Link href={detailsPath}>{name}</Link>
      {managedBySlug && (
        <span className={styles['managed-by']}>
          (managed by{' '}
          <Link inline href={businessCustomPropertyDefinitionStafftoolsListPath({enterprise: managedBySlug})}>
            {managedBySlug}
          </Link>
          )
        </span>
      )}
    </>
  )
}
