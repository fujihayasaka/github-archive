import type {ActionListing} from '@github-ui/marketplace-common'
import {OverviewHeader} from '../OverviewHeader'
import {About} from './About'
import {Tags} from './Tags'
import type {Repository} from '../../types'
import {ListingBreadcrumbs} from '../ListingBreadcrumbs'
import {DelistButton} from './DelistButton'

interface HeaderProps {
  action: ActionListing
  repository: Repository
  delistActionData: {
    hydroAttrs: {[key: string]: string}
    repoAdminableByViewer: boolean
  }
}

export function Header(props: HeaderProps) {
  const {action, repository, delistActionData} = props

  return (
    <OverviewHeader
      listing={action}
      breadcrumbs={<ListingBreadcrumbs listing={action} />}
      delistButton={<DelistButton action={action} delistActionData={delistActionData} />}
      listingDetails={<About action={action} repository={repository} />}
      additonalDetails={<Tags tags={action.categories} />}
    />
  )
}
