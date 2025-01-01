import type {Meta, StoryObj} from '@storybook/react'
import {RoutesContext} from '@github-ui/react-core/routes-context'
import {MemoryRouter, Routes, Route} from 'react-router-dom'

import {default as WelcomeBannerComponent} from './WelcomeBanner'

const meta: Meta<typeof WelcomeBannerComponent> = {
  title: 'Apps/Billing/WelcomeBanner',
  component: WelcomeBannerComponent,
  argTypes: {},
}

export default meta
type Story = StoryObj<typeof WelcomeBannerComponent>

export const NotEnterprise: Story = {
  render: args => <WelcomeBannerComponent {...args} />,
  args: {
    multiTenant: false,
    isEnterprise: false,
  },
  decorators: [
    Story => (
      <RoutesContext.Provider
        value={{
          routes: [],
        }}
      >
        <MemoryRouter initialEntries={['/organizations/foo']}>
          <Routes>
            <Route path="/organizations/:business" element={<Story />} />
          </Routes>
        </MemoryRouter>
      </RoutesContext.Provider>
    ),
  ],
}

export const NotMultiTenant: Story = {
  render: args => <WelcomeBannerComponent {...args} />,
  args: {
    multiTenant: false,
    isEnterprise: true,
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

export const MultiTenant: Story = {
  render: args => <WelcomeBannerComponent {...args} />,
  args: {
    multiTenant: true,
    isEnterprise: true,
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
