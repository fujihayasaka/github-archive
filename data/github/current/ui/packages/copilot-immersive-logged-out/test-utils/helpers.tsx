// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {EntitlementProvider} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {type CopilotChatModel, CopilotLicenseType} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {generateDefaultModel} from '@github-ui/copilot-chat/utils/models'
import type React from 'react'
import {useState} from 'react'

import {CopilotContext} from '../contexts/CopilotContext'

export const PROMPT_PATH = '/copilot/prompt'
export const SIGN_IN_PATH = '/login'
export const SIGN_UP_PATH = '/signup'
export const DEFAULT_MODEL = generateDefaultModel()

export function copilotWrapper({children}: React.PropsWithChildren) {
  // eslint-disable-next-line react-hooks/rules-of-hooks
  const [prompt, setPrompt] = useState('Testing this stuff')
  // eslint-disable-next-line react-hooks/rules-of-hooks
  const [selectedModel, setSelectedModel] = useState<CopilotChatModel>(DEFAULT_MODEL)
  return (
    <CopilotContext.Provider value={{prompt, setPrompt, selectedModel, setSelectedModel}}>
      <EntitlementProvider initialLicenseType={CopilotLicenseType.LicensedFull}>{children}</EntitlementProvider>
    </CopilotContext.Provider>
  )
}
