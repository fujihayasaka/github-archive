import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {getCopilotChatProviderProps} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import {AmbientErrorBanner} from './AmbientErrorBanner'

const meta = {
  title: 'Apps/Copilot/AmbientErrorBanner',
  component: AmbientErrorBanner,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof AmbientErrorBanner>

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
        <AmbientErrorBanner ambientError={{message: 'Some test error message'}} />
      </Container>
    )
  },
}
