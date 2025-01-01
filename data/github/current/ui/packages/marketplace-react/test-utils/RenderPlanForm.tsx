import {render, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {PlanForm} from '../components/apps/pricing-plans/PlanForm'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlan, mockPlanInfo} from './mock-data'
import type {Plan, PlanInfo} from '../types'
import type {AppListing} from '@github-ui/marketplace-common'

export const renderInPlanForm = (
  component: React.ReactNode,
  overrides?: {
    listing?: Partial<AppListing>
    planInfo?: Partial<PlanInfo>
    plan?: Partial<Plan>
  },
  options?: TestRenderOptions,
) => {
  const planInfo = mockPlanInfo(overrides?.planInfo)
  const props = {
    listing: mockAppListing(overrides?.listing),
    plan: mockPlan(overrides?.plan),
    planInfo,
    onAccountSelect: jest.fn(),
    selectedAccount: planInfo.selectedAccount,
  }

  return render(<PlanForm {...props}>{component}</PlanForm>, options)
}
