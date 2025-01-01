import {Contributors} from '../Contributors'
import {Resources} from './Resources'
import {ThirdPartyStatement} from './ThirdPartyStatement'
import {About} from './About'
import {VerifiedOwner} from '../sidebar-shared/VerifiedOwner'
import {Tags} from '../sidebar-shared/Tags'
import type {Repository, ReleaseData} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'

interface SidebarProps {
  action: ActionListing
  repository: Repository
  releaseData: ReleaseData
  repoAdminableByViewer: boolean
}

export function Sidebar(props: SidebarProps) {
  const {action, repository, releaseData, repoAdminableByViewer} = props
  const {isVerifiedOwner, categories} = action
  const {isThirdParty} = repository

  return (
    <>
      <About action={action} repository={repository} releaseData={releaseData} sidebar />
      <VerifiedOwner isVerifiedOwner={isVerifiedOwner} pageType="actions" />
      <Tags tags={categories} type="actions" />
      <Contributors repository={repository} />
      <Resources repository={repository} action={action} repoAdminableByViewer={repoAdminableByViewer} />
      <div className={'border-top color-border-muted pt-4'}>
        <ThirdPartyStatement isThirdParty={isThirdParty} name={action.name} />
      </div>
    </>
  )
}
