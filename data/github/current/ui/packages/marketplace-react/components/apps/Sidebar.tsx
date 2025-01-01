import type {AppListing} from '@github-ui/marketplace-common'
import type {PlanInfo} from '../../types'
import {About} from './About'
import {VerifiedOwner} from '../sidebar-shared/VerifiedOwner'
import {PlanInfo as SidebarPlanInfo} from './sidebar/PlanInfo'
import {Languages} from './sidebar/Languages'
import {WorksWith} from './sidebar/WorksWith'
import {Resources} from './sidebar/Resources'
import {Tags} from '../sidebar-shared/Tags'

export type SidebarProps = {
  app: AppListing
  supportedLanguages: string[]
  planInfo: PlanInfo
}

export function Sidebar({app, supportedLanguages, planInfo}: SidebarProps) {
  return (
    <>
      <About app={app} sidebar />
      <VerifiedOwner isVerifiedOwner={app.isVerifiedOwner} pageType="apps" />
      <Tags tags={app.categories} type="apps" />
      <SidebarPlanInfo planInfo={planInfo} isCopilotApp={app.copilotApp} />
      <WorksWith isCopilotApp={app.copilotApp} />
      <Languages supportedLanguages={supportedLanguages} />
      <Resources app={app} />
    </>
  )
}
