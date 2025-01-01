import type {CustomPropertyDetailsPagePayload, PropertyDefinition} from '@github-ui/custom-properties-types'
import {propertyDefinitionSettingsPath} from '@github-ui/paths'
import {Link} from '@github-ui/react-core/link'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {GearIcon, PencilIcon} from '@primer/octicons-react'
import {Box, Breadcrumbs, Button, LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useState} from 'react'

import {ServerErrorFormBanner} from '../components/Banners'
import {DefinitionDangerZone} from '../components/DefinitionDangerZone'
import {PropertyPageHeader} from '../components/PageHeader'
import {PropertyDefinitionSettings} from '../components/PropertyDefinitionSettings'
import {ReadOnlyPropertyDefinitionSettings} from '../components/ReadOnlyPropertyDefinitionSettings'
import {useListPropertiesPath} from '../hooks/use-properties-paths'
import {useEditPropertyPathBuilder} from '../hooks/use-property-details-paths'
import {usePropertySource} from '../hooks/use-property-source'

export function CustomPropertyDetailsPage() {
  const {propertyNames, definition, business, canManageBusiness, orgConflicts} =
    useRoutePayload<CustomPropertyDetailsPagePayload>()
  const [formError, setFormError] = useState('')
  const {settingsLevel} = usePropertySource()
  const [isEditing, setEditing] = useState(!definition)
  const canEdit = !!definition && settingsLevel === definition.sourceType

  const navigate = useNavigate()
  const listPropertiesPath = useListPropertiesPath()
  const propertyDetailsPathBuilder = useEditPropertyPathBuilder()
  const propertiesListExperienceEnabled = useFeatureFlag('enterprise_custom_properties_list')
  const propertiesPromotionEnabled = useFeatureFlag('enterprise_custom_properties_promotion')

  function returnToList() {
    navigate(listPropertiesPath)
  }

  function onSuccess(propertyName: string) {
    if (propertiesListExperienceEnabled) {
      setEditing(false)
      navigate(propertyDetailsPathBuilder(propertyName))
    } else {
      returnToList()
    }
  }

  function onCancel() {
    const isEditingExistingDefinition = !!definition
    if (propertiesListExperienceEnabled && isEditingExistingDefinition) {
      setEditing(false)
    } else {
      returnToList()
    }
  }

  const isBizPropInOrgContext = settingsLevel === 'org' && business && definition?.sourceType === 'business'
  const canDeleteProperty = settingsLevel === definition?.sourceType
  const canPromoteProperty =
    propertiesPromotionEnabled && settingsLevel === 'business' && definition?.sourceType === 'org'
  const showDangerZone = canDeleteProperty || canPromoteProperty

  return (
    <>
      {formError && (
        <Box sx={{mb: 3}}>
          <ServerErrorFormBanner>{formError}</ServerErrorFormBanner>
        </Box>
      )}

      <Header definition={definition} canEdit={canEdit} isEditing={isEditing} onEditClick={() => setEditing(true)} />

      {isBizPropInOrgContext && (
        <Banner
          className="mb-3 mt-2"
          title="Read only definition"
          hideTitle
          primaryAction={
            canManageBusiness && (
              <LinkButton
                leadingVisual={GearIcon}
                href={propertyDefinitionSettingsPath({
                  pathPrefix: 'enterprises',
                  sourceName: business.slug,
                  propertyName: definition.propertyName,
                })}
              >
                Manage in enterprise
              </LinkButton>
            )
          }
        >
          This property is managed by {business.name} and can&apos;t be edited here.
        </Banner>
      )}

      {definition && !isEditing ? (
        <div className="mt-3">
          <ReadOnlyPropertyDefinitionSettings definition={definition} />
          {showDangerZone && (
            <div className="mt-4">
              <DefinitionDangerZone
                business={business}
                orgConflicts={orgConflicts}
                definition={definition}
                canDelete={canDeleteProperty}
                canPromote={canPromoteProperty}
              />
            </div>
          )}
        </div>
      ) : (
        <Box
          sx={{
            borderTopWidth: '1px',
            borderTopStyle: 'solid',
            borderTopColor: 'border.default',
            marginTop: 'var(--base-size-12)',
            paddingTop: 3,
          }}
        >
          <PropertyDefinitionSettings
            definition={definition}
            existingPropertyNames={propertyNames}
            onCancel={onCancel}
            onSuccess={onSuccess}
            setFormError={setFormError}
          />
        </Box>
      )}
    </>
  )
}

interface HeaderProps {
  definition?: PropertyDefinition
  canEdit: boolean
  isEditing: boolean
  onEditClick(): void
}

function Header({definition, canEdit, isEditing, onEditClick}: HeaderProps) {
  const definitionsListPath = useListPropertiesPath()

  return (
    <>
      <Breadcrumbs sx={{marginBottom: 2}}>
        <Breadcrumbs.Item as={Link} to={definitionsListPath}>
          Custom properties
        </Breadcrumbs.Item>
        <Breadcrumbs.Item selected>{definition?.propertyName || 'New property'}</Breadcrumbs.Item>
      </Breadcrumbs>
      <PropertyPageHeader
        title={<div>{definition?.propertyName || 'New property'}</div>}
        actions={
          definition &&
          canEdit &&
          !isEditing && (
            <Button sx={{ml: 3}} onClick={onEditClick} leadingVisual={PencilIcon}>
              Edit
            </Button>
          )
        }
      />
    </>
  )
}
