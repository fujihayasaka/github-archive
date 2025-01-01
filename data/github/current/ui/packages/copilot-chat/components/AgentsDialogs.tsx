import {useCustomCopilotsEnabled} from '@github-ui/custom-copilots/hooks'
import {AlertIcon, TelescopeIcon} from '@primer/octicons-react'
import {Box, Button, Link} from '@primer/react'
import {Dialog} from '@primer/react/experimental'

import {AGENTS_MARKETPLACE_URL} from '../utils/agents-helpers'
import type {CopilotChatModel} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {useDefaultModel} from '../utils/models'

export function NoAgentsAvailableDialog({onClose}: {onClose: () => void}) {
  return (
    <Dialog
      width="large"
      title="Extensions"
      position={{
        narrow: 'fullscreen',
        regular: 'center',
      }}
      onClose={onClose}
      renderBody={() => (
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            textAlign: 'center',
            alignItems: 'center',
            justifyContent: 'center',
            px: 4,
            py: 8,
            flex: 1,
            height: '100%',
          }}
        >
          <Box
            sx={{
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'center',
              alignItems: 'center',
              gap: 2,
              color: 'fg.muted',
            }}
          >
            <TelescopeIcon size={24} />
            <Box as="h3" sx={{fontSize: 2, fontWeight: 'bold', mt: 2, color: 'fg.default'}}>
              Chat with your favorite tools and services
            </Box>
            <Box as="p" sx={{fontSize: 1, fontWeight: 'normal'}}>
              Browse the marketplace to find extensions for the tools and services you rely on
            </Box>
            <Button as="a" href={AGENTS_MARKETPLACE_URL}>
              Browse marketplace
            </Button>
            <Box sx={{mt: 2}}>
              <Link href="https://gh.io/copilot-extensions-docs">Documentation</Link>
            </Box>
          </Box>
        </Box>
      )}
    />
  )
}

export function AgentsNotSupportedDialog({onClose}: {onClose: () => void}) {
  const manager = useChatManager()
  const state = useChatState()
  const customCopilotsEnabled = useCustomCopilotsEnabled()
  const defaultModel: CopilotChatModel = useDefaultModel(state.availableModels)

  return (
    <Dialog
      width="large"
      title="Extensions"
      position={{
        narrow: 'fullscreen',
        regular: 'center',
      }}
      onClose={onClose}
      renderBody={() => (
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            textAlign: 'center',
            px: 4,
            py: 10,
            height: '100%',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Box
            sx={{
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'center',
              alignItems: 'center',
              gap: 2,
              color: 'fg.muted',
            }}
          >
            <Box sx={{display: 'flex', color: 'attention.fg'}}>
              <AlertIcon size={24} />
            </Box>
            <Box as="h3" sx={{fontSize: 2, fontWeight: 'bold', mt: 2, color: 'fg.default'}}>
              {customCopilotsEnabled ? 'Copilots and extensions' : 'Extensions'} aren&apos;t supported by this model
            </Box>
            <Box as="p" sx={{fontSize: 1, fontWeight: 'normal'}}>
              Switch back to the {defaultModel.displayName} model or start a new conversation
            </Box>
            <Button
              onClick={() => {
                void manager.selectThread(null)
                void manager.selectModel(defaultModel)
              }}
            >
              New conversation
            </Button>
          </Box>
        </Box>
      )}
    />
  )
}
