import {Stack} from '@primer/react'
import {Contributors} from '../Contributors'
import {Resources} from './Resources'
import {ThirdPartyStatement} from './ThirdPartyStatement'
import {About} from './About'
import {VerifiedOwner} from './VerifiedOwner'
import {Tags} from './Tags'
import type {Repository} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'

interface SidebarProps {
  action: ActionListing
  repository: Repository
}

export function Sidebar(props: SidebarProps) {
  const {action, repository} = props
  const {isVerifiedOwner, categories} = action
  const {isThirdParty} = repository

  return (
    <Stack gap={'spacious'}>
      <About action={action} repository={repository} sidebar />
      <VerifiedOwner isVerifiedOwner={isVerifiedOwner} />
      <Tags tags={categories} />
      <Contributors repository={repository} />
      <Resources repository={repository} action={action} />
      <div className={'border-top color-border-muted pt-4'}>
        <ThirdPartyStatement isThirdParty={isThirdParty} name={repository.name} />
      </div>
    </Stack>
  )
}
