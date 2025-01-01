import type {PropertyDefinition} from '@github-ui/custom-properties-types'
import {clsx} from 'clsx'
import type {PropsWithChildren} from 'react'

import {definitionTypeLabels} from '../helpers/definition-type-labels'
import styles from './ReadOnlyPropertyDefinitionSettings.module.css'

interface Props {
  definition: PropertyDefinition
}

export function ReadOnlyPropertyDefinitionSettings({definition}: Props) {
  const isText = definition.valueType === 'string'

  return (
    <div data-testid="readonly-property-definitions-settings" data-hpc className="border rounded-2">
      <div className="border-bottom text-bold bgColor-inset rounded-top-2 p-3">Property attributes</div>
      <DataRow label="Name">{definition.propertyName}</DataRow>
      <DataRow label="Description">{definition.description}</DataRow>
      <DataRow label="Type">{definitionTypeLabels[definition.valueType]}</DataRow>
      {definition.allowedValues && <DataRow label="Options">{definition.allowedValues.join(', ')}</DataRow>}
      {isText && (
        <>
          <DataRow label="Match regular expression">{definition.regex ? 'Enabled' : 'Disabled'}</DataRow>
          {definition.regex && <DataRow label="Expression">{definition.regex}</DataRow>}
        </>
      )}
      <DataRow label="Allow repository actors to set this property">
        {definition.valuesEditableBy === 'org_and_repo_actors' ? 'Enabled' : 'Disabled'}
      </DataRow>
      <DataRow label="Require this property for new repositories">
        {definition.defaultValue ? 'Enabled' : 'Disabled'}
      </DataRow>
      {definition.defaultValue && (
        <DataRow label="Default value">
          {Array.isArray(definition.defaultValue) ? definition.defaultValue.join(', ') : definition.defaultValue}
        </DataRow>
      )}
    </div>
  )
}

type DataRowProps = PropsWithChildren<{
  label: string
}>

function DataRow({label, children}: DataRowProps) {
  return (
    <div className={clsx(styles.dataRow, 'px-3 py-2')}>
      <div className={clsx(styles.dataRowTitle, 'text-bold')}>{label}</div>
      <div className={styles.dataRowValue}>{children}</div>
    </div>
  )
}
