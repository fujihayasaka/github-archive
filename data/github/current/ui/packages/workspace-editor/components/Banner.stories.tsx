import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {useMemo} from 'react'

import {CopilotLicenseType, CopilotPlan} from '../../copilot-chat/utils/copilot-chat-types'
import {initialState, WorkbenchStoreContext} from '../../workbench/contexts/WorkbenchStoreContext'
import {EntitledService} from '../../workbench/utilities/workbench-store-reducer'
import {CurrentPullRequestProvider} from '../contexts/CurrentPullRequestProvider'
import {WorkspaceEditorUIProvider} from '../contexts/WorkspaceEditorUIContext'
import {getWorkspaceEditorRoutePayload} from '../test-utils/mock-data'
import {Banner} from './Banner'

const routePayload = getWorkspaceEditorRoutePayload()

const meta: Meta<typeof WrappedComponent> = {
  title: 'Apps/Workspace Editor/Components/Banner',
  component: Banner,
  parameters: {
    enabledFeatures: ['copilot_workbench_user_limits', 'spark_unlimited_dev_compute'],
  },
  argTypes: {
    canPurchaseAdditionalQuota: {
      control: 'boolean',
      table: {
        summary: false,
        category: 'useEntitlement',
      },
    },
    canUpgradePlan: {
      control: 'boolean',
      table: {
        summary: false,
        category: 'useEntitlement',
      },
    },
    chatQuotaRemaining: {
      control: {
        type: 'number',
        max: 20,
        min: 0,
        step: 1,
      },
      table: {
        summary: 20,
        category: 'useEntitlement',
      },
    },
    overagesEnabled: {
      control: 'boolean',
      table: {
        summary: false,
        category: 'useEntitlement',
      },
    },
    plan: {
      control: 'radio',
      options: Object.values(CopilotPlan),
      table: {
        summary: CopilotPlan.IndividualFree,
        category: 'useEntitlement',
      },
    },
    premiumChatQuotaRemaining: {
      control: {
        type: 'number',
        max: 100,
        min: 0,
        step: 1,
      },
      table: {
        summary: 100,
        category: 'useEntitlement',
      },
    },
    licenseType: {
      control: 'radio',
      options: Object.values(CopilotLicenseType),
      table: {
        summary: CopilotLicenseType.LicensedLimited,
        category: 'useEntitlement',
      },
    },
    reloadQuota: {
      action: 'useEntitlement().reloadQuota()',
      table: {
        disable: true,
      },
    },
  },
  decorators: [
    Story => (
      <WorkspaceEditorUIProvider>
        <CurrentPullRequestProvider>
          <div style={{maxWidth: '800px', margin: '20px'}}>
            <Story />
          </div>
        </CurrentPullRequestProvider>
      </WorkspaceEditorUIProvider>
    ),
    storyWrapper({routePayload: {...routePayload, copilotAccessAllowed: true}}),
  ],
}

export default meta

const defaultArgs = {
  canPurchaseAdditionalQuota: true,
  canUpgradePlan: true,
  chatQuotaRemaining: 20,
  overagesEnabled: true,
  plan: CopilotPlan.IndividualFree as CopilotPlan,
  premiumChatQuotaRemaining: 100,
  resetDate: new Date().toJSON().slice(0, 'XXXX-XX-XX'.length),
  licenseType: CopilotLicenseType.LicensedLimited as CopilotLicenseType,
  reloadQuota: () => {},
}

type WrapperComponentProps = typeof defaultArgs

export const Default = {
  name: 'Banner',
  args: defaultArgs,
  render: (args: WrapperComponentProps) => <WrappedComponent {...args} />,
}
const WrappedComponent = ({
  chatQuotaRemaining,
  overagesEnabled,
  plan,
  premiumChatQuotaRemaining,
  resetDate,
  licenseType,
}: WrapperComponentProps) => {
  const workbenchStoreValue = useMemo(() => {
    return {
      ...initialState,
      hasServiceErrors: false,
      entitlement: {
        ...initialState.entitlement,
        [EntitledService.COPILOT]: {
          licenseType,
          plan,
          quotas: {
            limits: {
              chat: 100,
              premiumInteractions: 50,
            },
            remaining: {
              chat: chatQuotaRemaining,
              chatPercentage: chatQuotaRemaining / 100,
              premiumInteractions: premiumChatQuotaRemaining,
              premiumInteractionsPercentage: premiumChatQuotaRemaining / 50,
            },
            resetDate,
            overagesEnabled,
          },
        },
      },
      setReadOnly: () => {},
      onError: () => {},
      onConnected: () => {},
      onDisconnected: () => {},
      onIdle: () => {},
      onStatus: () => {},
      onEntitlement: () => {},
      onEntitlements: () => {},
      onCodespaceStatus: () => {},
      onSuccess: () => {},
      reloadQuota: () => {},
    }
  }, [chatQuotaRemaining, licenseType, overagesEnabled, plan, premiumChatQuotaRemaining, resetDate])
  return (
    <WorkbenchStoreContext.Provider value={workbenchStoreValue}>
      <Banner />
    </WorkbenchStoreContext.Provider>
  )
}
