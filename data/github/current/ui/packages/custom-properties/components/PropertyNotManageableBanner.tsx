import type {PropertySourceDetails} from '@github-ui/custom-properties-types'
import {propertyDefinitionSettingsPath} from '@github-ui/paths'
import {GearIcon} from '@primer/octicons-react'
import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'

export function PropertyNotManageableBanner({
  propertySource,
  propertyName,
  viewerCanManage,
}: {
  propertySource: PropertySourceDetails
  propertyName: string
  viewerCanManage: boolean
}) {
  return (
    <Banner
      className="mb-3 mt-2"
      title="Read only definition"
      hideTitle
      primaryAction={viewerCanManage && <ManageLink propertySource={propertySource} propertyName={propertyName} />}
    >
      This property is managed by {propertySource.name} and can&apos;t be edited here.
    </Banner>
  )
}

function ManageLink({propertySource, propertyName}: {propertySource: PropertySourceDetails; propertyName: string}) {
  const {type, slug} = propertySource

  const pathPrefix = type === 'business' ? 'enterprises' : 'organizations'

  return (
    <LinkButton
      leadingVisual={GearIcon}
      href={propertyDefinitionSettingsPath({
        pathPrefix,
        sourceName: slug,
        propertyName,
      })}
    >
      {`Manage in ${type === 'business' ? 'enterprise' : 'organization'}`}
    </LinkButton>
  )
}
