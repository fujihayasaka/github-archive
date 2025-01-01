import {Breadcrumbs} from '@primer/react'
import type {Model} from '@github-ui/marketplace-common'
import {normalizeModelPublisher} from '../../../../utils/normalize-model-strings'

export function BreadcrumbHeader({model}: {model: Model}) {
  return (
    <Breadcrumbs>
      <Breadcrumbs.Item href="/marketplace">Marketplace</Breadcrumbs.Item>
      <Breadcrumbs.Item href="/marketplace/models">Models</Breadcrumbs.Item>
      <Breadcrumbs.Item href="" selected>
        {normalizeModelPublisher(model.publisher)}
      </Breadcrumbs.Item>
    </Breadcrumbs>
  )
}
