import {getControlLabel} from '@github-ui/custom-properties-editing'
import type {
  PropertyDefinition,
  PropertySourceDetails,
  SourceInfo,
  SourceType,
} from '@github-ui/custom-properties-types'
import {human} from '@github-ui/formatters'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemDescriptionItem} from '@github-ui/list-view/ListItemDescriptionItem'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {enterprisePath, ownerPath} from '@github-ui/paths'
import {Link} from '@github-ui/react-core/link'
import {ShieldLockIcon} from '@primer/octicons-react'
import {Link as PrimerLink, Truncate} from '@primer/react'
import {memo} from 'react'

import {definitionTypeLabels} from '../helpers/definition-type-labels'
import {useEditPropertyPath} from '../hooks/use-property-details-paths'
import {usePropertySource} from '../hooks/use-property-source'
import styles from './DefinitionsList.module.css'
import {EmptyState} from './EmptyState'

interface Props {
  definitions: PropertyDefinition[]
  totalCount: number
}
export function DefinitionsList({definitions, totalCount}: Props) {
  if (definitions.length === 0) {
    return <EmptyState>No properties have been found</EmptyState>
  }

  return (
    <div data-hpc data-testid="repos-definitions-list" className={styles.definitionsListContainer}>
      <ListView
        title="Property definitions"
        metadata={
          <ListViewMetadata
            className="rounded-top-2"
            title={
              <span className={styles.propertiesCountText}>
                {human(totalCount, {suffix: false})} {totalCount === 1 ? 'property' : 'properties'}
              </span>
            }
          />
        }
      >
        {definitions.map(definition => (
          <DefinitionListItem key={definition.propertyName + definition.source.slug} definition={definition} />
        ))}
      </ListView>
    </div>
  )
}

interface DefinitionListItemProps {
  definition: PropertyDefinition
}

const DefinitionListItem = memo(({definition}: DefinitionListItemProps) => {
  const editPropertyPath = useEditPropertyPath(definition)
  const {settingsLevel} = usePropertySource()

  return (
    <>
      <ListItem
        className={styles.listItem}
        title={
          <ListItemTitle
            value={getControlLabel(definition)}
            href="#"
            linkProps={{
              as: Link,
              to: editPropertyPath,
            }}
            containerClassName={styles.ListItemTitle}
          />
        }
        metadata={<DefinitionMetadata {...{definition, settingsLevel}} />}
        metadataContainerClassName={styles.metadataContainer}
      >
        <ListItemMainContent>
          {definition.description && (
            <ListItemDescription className={styles.ListItemDescription}>
              <ListItemDescriptionItem className={styles.ListItemDescriptionItem}>
                {definition.description}
              </ListItemDescriptionItem>
            </ListItemDescription>
          )}
        </ListItemMainContent>
      </ListItem>
    </>
  )
})
DefinitionListItem.displayName = 'DefinitionListItem'

interface DefinitionMetadataItemProps extends DefinitionListItemProps {
  settingsLevel: SourceType
}
function DefinitionMetadata(props: DefinitionMetadataItemProps) {
  const {definition} = props
  return (
    <>
      <ListItemMetadata>
        <span>{definitionTypeLabels[definition.valueType] || ''}</span>
      </ListItemMetadata>
      <ListItemMetadata className={styles.listItemMetadata}>
        <ManagedByLabel {...props} />
      </ListItemMetadata>
    </>
  )
}

function ManagedByLabel({definition, settingsLevel}: DefinitionMetadataItemProps) {
  const {source} = definition
  const managedByLabelComponent = (() => {
    if (settingsLevel === 'org' && source.type === 'business') {
      return <OrgLevelManagedByBusinessLabel business={source} />
    }
    if (settingsLevel === 'business') {
      return <BusinessLevelManagedBySourceLabel propertySource={source} />
    }
  })()

  return (
    managedByLabelComponent && (
      <>
        <span className="mx-2">•</span>
        <div data-testid={`${definition.propertyName}-managed-by-label`} className={styles.managedByLabelContainer}>
          {managedByLabelComponent}
        </div>
      </>
    )
  )
}

function BusinessLevelManagedBySourceLabel({propertySource}: {propertySource: PropertySourceDetails}) {
  const {slug, name, type} = propertySource
  const sourcePath = type === 'business' ? enterprisePath({slug}) : ownerPath({owner: slug})
  return (
    <div className="d-flex flex-row flex-items-center gap-1">
      <span className="color-fg-muted">Managed by </span>
      <PrimerLink inline href={sourcePath}>
        <Truncate title={name}>{name}</Truncate>
      </PrimerLink>
    </div>
  )
}

function OrgLevelManagedByBusinessLabel({business}: {business: SourceInfo}) {
  const {slug, name} = business
  return (
    <div className="d-flex flex-row flex-items-center gap-1">
      <ShieldLockIcon className="color-fg-muted" size={'small'} />
      <span className="color-fg-muted">Managed by </span>
      <PrimerLink inline href={enterprisePath({slug})}>
        <Truncate title={name}>{name}</Truncate>
      </PrimerLink>
    </div>
  )
}
