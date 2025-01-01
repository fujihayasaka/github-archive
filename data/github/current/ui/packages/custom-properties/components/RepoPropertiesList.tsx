import {CustomPropertyValuesTable} from '@github-ui/custom-properties-editing'
import type {PropertyField} from '@github-ui/custom-properties-editing/use-edit-custom-properties'
import type {PropertyDefinition, PropertyValuesRecord} from '@github-ui/custom-properties-types'
import {SearchIcon} from '@primer/octicons-react'
import {Link, TextInput} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {useState} from 'react'

import {useCurrentOrg} from '../contexts/CurrentOrgRepoContext'
import styles from './RepoPropertiesList.module.css'

interface Props {
  definitions: PropertyDefinition[]
  values: PropertyValuesRecord
}

function transformPropertyValues(data: PropertyValuesRecord) {
  const outputData: Record<string, PropertyField> = {}

  for (const [propertyName, value] of Object.entries(data)) {
    outputData[propertyName] = {
      value,
      changed: false,
      propertyName,
      mixed: false,
    }
  }

  return outputData
}

export function RepoPropertiesList({definitions, values}: Props) {
  const [filterTerm, setFilterTerm] = useState('')
  const propertyValuesMap = transformPropertyValues(values)

  const orgName = useCurrentOrg().login

  if (definitions.length === 0) {
    return (
      <Blankslate border>
        <Blankslate.Heading>No custom properties set for this repository.</Blankslate.Heading>
        <Blankslate.Description>
          <Link
            inline
            href="https://docs.github.com/enterprise-cloud@latest/organizations/managing-organization-settings/managing-custom-properties-for-repositories-in-your-organization"
          >
            Learn more about custom properties
          </Link>{' '}
          and how to set them at the organization level.
        </Blankslate.Description>
      </Blankslate>
    )
  }

  const filteredDefinitions = definitions.filter(getFilterPredicate(filterTerm))

  return (
    <div className={styles.propertiesListContainer}>
      <TextInput
        block
        value={filterTerm}
        onChange={e => setFilterTerm(e.target.value)}
        leadingVisual={SearchIcon}
        aria-label="Filter"
        placeholder="Filter properties"
      />
      <div data-hpc>
        {filteredDefinitions.length ? (
          <CustomPropertyValuesTable
            definitions={filteredDefinitions}
            propertyValuesMap={propertyValuesMap}
            showLockMessages={false}
            orgName={orgName}
          />
        ) : (
          <Blankslate border>
            <Blankslate.Heading>No properties that match</Blankslate.Heading>
          </Blankslate>
        )}
      </div>
    </div>
  )
}

function getFilterPredicate(term: string) {
  return (item: PropertyDefinition) => item.propertyName.toLowerCase().includes(term.toLowerCase())
}
