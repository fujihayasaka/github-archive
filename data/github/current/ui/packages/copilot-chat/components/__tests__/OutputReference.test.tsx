import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {getCopilotChatProviderProps, getThirdPartyReferenceMock} from '../../test-utils/mock-data'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {OutputReference} from '../ChatReference'
import {MessagesPortalContainer} from '../PortalContainerUtils'

describe('OutputReference', () => {
  describe('third-party references', () => {
    test('renders the displayName', () => {
      const props = getCopilotChatProviderProps()

      render(
        <CopilotChatProvider {...props} topic={undefined} threadId="2" mode="immersive">
          <OutputReference reference={getThirdPartyReferenceMock({displayName: 'Arrr blackbeard arrr'})} />
        </CopilotChatProvider>,
      )
      const reference = screen.getByText('Arrr blackbeard arrr')
      expect(reference).toBeInTheDocument()
    })

    test(`renders the 'Open' link in the action list if the reference has a displayUrl and in immersive mode`, async () => {
      const props = getCopilotChatProviderProps()

      const {user} = render(
        <CopilotChatProvider {...props} topic={undefined} threadId="2" mode="immersive">
          <MessagesPortalContainer />
          <OutputReference reference={getThirdPartyReferenceMock({displayUrl: 'http://www.example.com'})} />
        </CopilotChatProvider>,
      )
      await user.click(screen.getByRole('button', {name: 'More reference options'}))

      const reference = await screen.findByText('Open')
      expect(reference).toBeInTheDocument()
    })

    test('does not render the link in the action list if the reference does not have a displayUrl', async () => {
      const props = getCopilotChatProviderProps()

      const {user} = render(
        <CopilotChatProvider {...props} topic={undefined} threadId="2" mode="immersive">
          <MessagesPortalContainer />
          <OutputReference reference={getThirdPartyReferenceMock({displayUrl: ''})} />
        </CopilotChatProvider>,
      )
      await user.click(screen.getByRole('button', {name: 'More reference options'}))

      const reference = screen.queryByText('Open')
      expect(reference).not.toBeInTheDocument()
    })

    test(`renders the 'Open' link in the action list in assistive mode too, not 'Preview'`, async () => {
      const props = getCopilotChatProviderProps()

      const {user} = render(
        <CopilotChatProvider {...props} topic={undefined} threadId="2" mode="assistive">
          <MessagesPortalContainer />
          <OutputReference reference={getThirdPartyReferenceMock({displayUrl: 'http://www.example.com'})} />
        </CopilotChatProvider>,
      )
      await user.click(screen.getByRole('button', {name: 'More reference options'}))

      const reference = await screen.findByText('Open')
      expect(reference).toBeInTheDocument()

      const preview = screen.queryByText('Preview')
      expect(preview).not.toBeInTheDocument()
    })
  })
})
