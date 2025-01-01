import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {getCopilotChatProviderProps} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import {LegalDisclaimer} from './LegalDisclaimer'

const meta = {
  title: 'Apps/Copilot/LegalDisclaimer',
  component: LegalDisclaimer,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof LegalDisclaimer>

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
        <LegalDisclaimer />
      </Container>
    )
  },
}
