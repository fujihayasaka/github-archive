import {Breadcrumbs} from '@primer/react-brand'

import type {PrimerComponentBreadcrumb} from '../../../schemas/contentful/contentTypes/primerComponentBreadcrumb'

import {ContentfulBreadcrumb} from '../ContentfulBreadcrumb/ContentfulBreadcrumb'

export type ContentfulBreadcrumbsProps = {
  breadcrumbs: PrimerComponentBreadcrumb[]
  variant?: 'default' | 'accent'
}

export function ContentfulBreadcrumbs({breadcrumbs, variant}: ContentfulBreadcrumbsProps) {
  return (
    <Breadcrumbs variant={variant}>
      {breadcrumbs.map(breadcrumb => (
        <ContentfulBreadcrumb key={breadcrumb.sys.id} component={breadcrumb} />
      ))}
    </Breadcrumbs>
  )
}
