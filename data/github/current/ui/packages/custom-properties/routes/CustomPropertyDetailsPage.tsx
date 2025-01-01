import type {CustomPropertyDetailsPagePayload, PropertyDefinition} from '@github-ui/custom-properties-types'
import {Link} from '@github-ui/react-core/link'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {type SafeHTMLString, SafeHTMLText} from '@github-ui/safe-html'
import {useNavigate} from '@github-ui/use-navigate'
import {PencilIcon} from '@primer/octicons-react'
import {Breadcrumbs, Button} from '@primer/react'
import {useEffect, useRef, useState} from 'react'

import {ServerErrorFormBanner} from '../components/Banners'
import {DefinitionDangerZone} from '../components/DefinitionDangerZone'
import {PropertyPageHeader} from '../components/PageHeader'
import {PropertyDefinitionSettings} from '../components/PropertyDefinitionSettings'
import {PropertyNotManageableBanner} from '../components/PropertyNotManageableBanner'
import {ReadOnlyPropertyDefinitionSettings} from '../components/ReadOnlyPropertyDefinitionSettings'
import {useListPropertiesPath} from '../hooks/use-properties-paths'
import {useEditPropertyPathBuilder} from '../hooks/use-property-details-paths'
import {usePropertySource} from '../hooks/use-property-source'
import styles from './CustomPropertyDetailsPage.module.css'

export function CustomPropertyDetailsPage() {
  const {propertyNames, definition, business, canManageProperty, orgConflicts} =
    useRoutePayload<CustomPropertyDetailsPagePayload>()
  const [formError, setFormError] = useState<SafeHTMLString>('' as SafeHTMLString)
  const {settingsLevel} = usePropertySource()
  const [isEditing, setEditing] = useState(!definition)
  const canEdit = !!definition && settingsLevel === definition.source.type

  const navigate = useNavigate()
  const listPropertiesPath = useListPropertiesPath()
  const propertyDetailsPathBuilder = useEditPropertyPathBuilder()

  function returnToList() {
    navigate(listPropertiesPath)
  }

  function onSuccess(propertyName: string) {
    setEditing(false)
    navigate(propertyDetailsPathBuilder(propertyName))
  }

  function onCancel() {
    const isEditingExistingDefinition = !!definition
    if (isEditingExistingDefinition) {
      setEditing(false)
    } else {
      returnToList()
    }
  }

  const isPropNotManagedByThisContext = definition && definition.source.type !== settingsLevel
  const canDeleteProperty = settingsLevel === definition?.source?.type
  const canPromoteProperty = settingsLevel === 'business' && definition?.source.type === 'org'
  const showDangerZone = canDeleteProperty || canPromoteProperty

  const serverErrorBannerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    serverErrorBannerRef.current?.focus()
  }, [formError, serverErrorBannerRef])

  return (
    <>
      {formError && (
        <div className={styles.errorContainer}>
          <ServerErrorFormBanner ref={serverErrorBannerRef}>
            <SafeHTMLText html={formError} />
          </ServerErrorFormBanner>
        </div>
      )}
      <Header definition={definition} canEdit={canEdit} isEditing={isEditing} onEditClick={() => setEditing(true)} />
      {isPropNotManagedByThisContext && (
        <PropertyNotManageableBanner
          propertySource={definition.source}
          propertyName={definition.propertyName}
          viewerCanManage={canManageProperty}
        />
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
        <div className={styles.settingsFormContainer}>
          <PropertyDefinitionSettings
            definition={definition}
            existingPropertyNames={propertyNames}
            onCancel={onCancel}
            onSuccess={onSuccess}
            setFormError={setFormError}
          />
        </div>
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
      <Breadcrumbs className={styles.pageNavigationBreadcrumbs}>
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
            <Button className="ml-3 f5 text-semibold" onClick={onEditClick} leadingVisual={PencilIcon}>
              Edit
            </Button>
          )
        }
      />
    </>
  )
}
