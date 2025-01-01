import {generateDefaultModel} from '@github-ui/copilot-chat/utils/models'
import type React from 'react'
import {useEffect, useMemo, useRef, useState} from 'react'
import {useSearchParams} from 'react-router-dom'

import {ChatInput} from '../components/ChatInput'
import {CopilotHeader} from '../components/CopilotHeader'
import type {CopilotContextValue} from '../contexts/CopilotContext'
import {CopilotContext} from '../contexts/CopilotContext'

const CopilotImmersiveLoggedOut: React.FC = () => {
  const [searchParams, setSearchParams] = useSearchParams()
  const [prompt, setPrompt] = useState('')
  const defaultModel = generateDefaultModel()
  const [selectedModel, setSelectedModel] = useState(defaultModel)
  const [initialModelID, setinitialModelID] = useState<string | null>(null)
  const autoPopulated = useRef(false)

  useEffect(() => {
    if (autoPopulated.current) return
    autoPopulated.current = true

    const queryPrompt = searchParams.get('prompt')
    if (queryPrompt) setPrompt(queryPrompt)

    const queryModelID = searchParams.get('model')
    setinitialModelID(queryModelID)

    const newSearchParams = new URLSearchParams(searchParams)
    newSearchParams.delete('prompt')
    newSearchParams.delete('model')
    setSearchParams(newSearchParams, {replace: true})
  }, [searchParams, setSearchParams])

  const copilotContextValue: CopilotContextValue = useMemo(() => {
    return {
      prompt,
      setPrompt,
      selectedModel,
      setSelectedModel,
    }
  }, [prompt, selectedModel])

  return (
    <>
      <CopilotHeader />
      <CopilotContext.Provider value={copilotContextValue}>
        <ChatInput initialModelID={initialModelID} />
      </CopilotContext.Provider>
    </>
  )
}

export default CopilotImmersiveLoggedOut
