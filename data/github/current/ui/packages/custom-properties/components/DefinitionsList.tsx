import {getControlLabel} from '@github-ui/custom-properties-editing'
import type {PropertyDefinition, PropertySourceDetails, SourceInfo} from '@github-ui/custom-properties-types'
import {human} from '@github-ui/formatters'
import {GitHubAvatar} from '@github-ui/github-avatar'
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
import {Box, Link as PrimerLink, Text, Truncate} from '@primer/react'
import {memo} from 'react'

import {definitionTypeLabels} from '../helpers/definition-type-labels'
import {useEditPropertyPath} from '../hooks/use-property-details-paths'
import {usePropertySource} from '../hooks/use-property-source'
import styles from './DefinitionsList.module.css'
import {EmptyState} from './EmptyState'

interface Props {
  business?: SourceInfo
  definitions: PropertyDefinition[]
  totalCount: number
}
export function DefinitionsList({definitions, business, totalCount}: Props) {
  if (definitions.length === 0) {
    return <EmptyState>No properties have been found</EmptyState>
  }

  return (
    <Box
      data-hpc
      sx={{border: '1px solid', borderColor: 'border.muted', borderRadius: 2}}
      data-testid="repos-definitions-list"
    >
      <ListView
        title="Property definitions"
        metadata={
          <ListViewMetadata
            className="rounded-top-2"
            title={
              <Text sx={{fontWeight: 'bold'}}>
                {human(totalCount, {suffix: false})} {totalCount === 1 ? 'property' : 'properties'}
              </Text>
            }
          />
        }
      >
        {definitions.map((definition, index) => (
          // index is to prevent key conflicts due to identical property names between organizations
          // TODO: use definition name + source name as key
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <DefinitionListItem key={index} definition={definition} business={business} />
        ))}
      </ListView>
    </Box>
  )
}

interface DefinitionListItemProps {
  definition: PropertyDefinition
  business?: SourceInfo
}

const DefinitionListItem = memo(({definition, business}: DefinitionListItemProps) => {
  const editPropertyPath = useEditPropertyPath(definition)
  const {settingsLevel} = usePropertySource()

  return (
    <>
      <ListItem
        className={styles.listItem}
        sx={{columnGap: 0, pl: 2}}
        title={
          <ListItemTitle
            value={getControlLabel(definition)}
            containerSx={{
              display: 'flex',
              flexFlow: 'row',
              alignItems: 'baseline',
              mx: 2,
            }}
            href="#"
            linkProps={{
              as: Link,
              to: editPropertyPath,
            }}
          />
        }
        metadataContainerSx={{
          display: 'flex',
          columnGap: [0, 0, 0, 5],
          rowGap: 1,
          flexWrap: ['wrap', 'wrap', 'wrap', 'nowrap'],
          mx: [2, 2, 2, 0],
          pb: [2, 2, 2, 0],
        }}
        metadata={
          <>
            <ListItemMetadata>
              <ManagedByLabel {...{definition, business, settingsLevel}} />
            </ListItemMetadata>
            <ListItemMetadata>
              <Text sx={{whiteSpace: 'nowrap', width: '82px'}}>{definitionTypeLabels[definition.valueType] || ''}</Text>
            </ListItemMetadata>
          </>
        }
      >
        <ListItemMainContent>
          {definition.description && (
            <ListItemDescription
              sx={{
                minWidth: 0,
                maxWidth: '100%',
                display: 'flex',
              }}
            >
              <ListItemDescriptionItem
                sx={{
                  display: 'block',
                  ml: 2,
                }}
              >
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

interface ManagedByLabelProps extends DefinitionListItemProps {
  settingsLevel: 'org' | 'business'
}

function ManagedByLabel({definition, business, settingsLevel}: ManagedByLabelProps) {
  const managedByLabelComponent = (() => {
    if (business && settingsLevel === 'org' && definition.sourceType === 'business') {
      return <OrgLevelManagedByBusinessLabel business={business} />
    }
    const propertySourceDetails = definition.source
    if (settingsLevel === 'business' && propertySourceDetails) {
      return <BusinessLevelManagedBySourceLabel propertySource={propertySourceDetails} />
    }
  })()

  return (
    managedByLabelComponent && (
      <>
        <Box sx={{display: 'inline'}} data-testid={`${definition.propertyName}-managed-by-label`}>
          {managedByLabelComponent}
        </Box>
        <span className="hide-xl mx-2">·</span>
      </>
    )
  )
}

function BusinessLevelManagedBySourceLabel({propertySource}: {propertySource: PropertySourceDetails}) {
  const {slug, name, avatarUrl, type} = propertySource
  const sourcePath = type === 'business' ? enterprisePath({slug}) : ownerPath({owner: slug})
  return (
    <>
      <Text sx={{color: 'fg.subtle'}}>
        <GitHubAvatar className="mr-1" src={avatarUrl} square /> Managed by{' '}
      </Text>
      <PrimerLink inline href={sourcePath}>
        <Truncate title={name}>{name}</Truncate>
      </PrimerLink>
    </>
  )
}

function OrgLevelManagedByBusinessLabel({business}: {business: SourceInfo}) {
  const {slug, name} = business
  return (
    <>
      <Text sx={{color: 'fg.subtle'}}>
        <ShieldLockIcon size={'small'} /> Managed by{' '}
      </Text>
      <PrimerLink inline href={enterprisePath({slug})}>
        <Truncate title={name}>{name}</Truncate>
      </PrimerLink>
    </>
  )
}
