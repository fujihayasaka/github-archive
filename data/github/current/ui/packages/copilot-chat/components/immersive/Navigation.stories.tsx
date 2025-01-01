import {Wrapper} from '@github-ui/react-core/test-utils'
import {HomeIcon} from '@primer/octicons-react'
import type {Meta, StoryObj} from '@storybook/react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {Navigation} from './Navigation'

const meta = {
  title: 'Apps/Copilot/Navigation',
  component: Navigation,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof Navigation>

export default meta

const Container = (props: {children: React.ReactNode}) => (
  <CopilotChatProvider {...getCopilotChatProviderProps()}>
    <Wrapper>{props.children}</Wrapper>
  </CopilotChatProvider>
)

export const Standalone: StoryObj = {
  render: () => {
    return (
      <Container>
        <ul>
          <Navigation displayName="Dashboard" href="" id="dashboard" aria-current="page" icon={HomeIcon} />
        </ul>
      </Container>
    )
  },
}
