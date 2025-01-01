import type {Meta, StoryObj} from '@storybook/react'
import {RoutesContext} from '@github-ui/react-core/routes-context'
import {MemoryRouter, Routes, Route} from 'react-router-dom'

import {default as BudgetBannerComponent} from './BudgetBanner'

const meta: Meta<typeof BudgetBannerComponent> = {
  title: 'Apps/Billing',
  component: BudgetBannerComponent,
  argTypes: {},
}

export default meta
type Story = StoryObj<typeof BudgetBannerComponent>

export const BudgetBanner: Story = {
  render: args => <BudgetBannerComponent {...args} />,
  args: {
    budgetAlertDetail: {
      text: "You've used 75% of your enterprise budget.",
      variant: 'warning',
      dismissible: false,
      dismiss_link: '',
      budget_id: 'test-budget-id',
    },
  },
  decorators: [
    Story => (
      <RoutesContext.Provider
        value={{
          routes: [],
        }}
      >
        <MemoryRouter
          initialEntries={['/enterprises/foo']}
          future={{v7_relativeSplatPath: true, v7_startTransition: true}}
        >
          <Routes>
            <Route path="/enterprises/:business" element={<Story />} />
          </Routes>
        </MemoryRouter>
      </RoutesContext.Provider>
    ),
  ],
}
