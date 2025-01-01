import {MenuPortalContainer} from '@github-ui/copilot-chat/components/PortalContainerUtils'
import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import {AppContext} from '@github-ui/react-core/app-context'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {Box} from '@primer/react'
import type {Meta} from '@storybook/react'
import {MemoryRouter} from 'react-router-dom'

import type {ThreadHeaderMenuProps} from './ThreadHeaderMenu'
import {ThreadHeaderMenu} from './ThreadHeaderMenu'

const meta = {
  title: 'Copilot/ThreadHeaderMenu',
  component: ThreadHeaderMenu,
  decorators: [
    Story => (
      <AppContext.Provider
        value={{
          routes: [jsonRoute({path: '/home', Component: ({children}: React.PropsWithChildren) => <>{children}</>})],
        }}
      >
        <MemoryRouter
          // eslint-disable-next-line camelcase
          future={{v7_relativeSplatPath: true, v7_startTransition: true}}
        >
          <Story />
        </MemoryRouter>
      </AppContext.Provider>
    ),
  ],
} satisfies Meta<typeof ThreadHeaderMenu>

export default meta

const defaultArgs: ThreadHeaderMenuProps = {
  setShowStaffDialog: () => {},
}

export const ThreadHeaderMenuExample = {
  args: {
    ...defaultArgs,
  },
  render: (props: ThreadHeaderMenuProps) => {
    return (
      <AppContext.Provider value={{routes: []}}>
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'start', gap: 4}}>
            <ThreadHeaderMenu setShowStaffDialog={props.setShowStaffDialog} />
          </Box>
          <MenuPortalContainer />
        </CopilotChatProvider>
      </AppContext.Provider>
    )
  },
}
