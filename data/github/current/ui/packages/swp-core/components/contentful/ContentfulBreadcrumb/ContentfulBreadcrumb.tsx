import {Breadcrumbs} from '@primer/react-brand'

import type {PrimerComponentBreadcrumb} from '../../../schemas/contentful/contentTypes/primerComponentBreadcrumb'

export type ContentfulBreadcrumbProps = {
  component: PrimerComponentBreadcrumb
}

export const ContentfulBreadcrumb = ({component}: ContentfulBreadcrumbProps) => {
  const {pageName, path, selected} = component.fields

  return (
    <Breadcrumbs.Item href={path} selected={selected}>
      {pageName}
    </Breadcrumbs.Item>
  )
}
