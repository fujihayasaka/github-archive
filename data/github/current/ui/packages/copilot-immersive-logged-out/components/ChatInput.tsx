import CopilotIconAnimation from '@github-ui/copilot-chat/components/CopilotIconAnimation'
import {LegalDisclaimer} from '@github-ui/copilot-chat/components/LegalDisclaimer'
import {EntitlementProvider} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import type {
  CopilotChatOrg,
  CopilotChatPayload,
  CopilotChatRepo,
  Docset,
  Icebreaker as ImportedIcebreaker,
  Icebreakers as ImportedIcebreakers,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {CopilotLicenseType} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {CommandIconButton} from '@github-ui/ui-commands'
import {PaperAirplaneIcon} from '@primer/octicons-react'
import {useEffect, useMemo, useRef, useState} from 'react'

import {useCopilotContext} from '../contexts/CopilotContext'
import styles from './ChatInput.module.css'
import data from './icebreakers.json'
import {ModelPicker} from './ModelPicker'
import {SignInDialog} from './SignInDialog'
import {SuggestionCard} from './SuggestionCard'

export interface CopilotImmersivePayload extends CopilotChatPayload {
  copilotChatSettingEnabled: boolean
  searchWorkerFilePath: string
  requestedTopic?: CopilotChatRepo | Docset
  ssoOrganizations: CopilotChatOrg[]
  copilotUpsellBannerDismissed: boolean
  icebreakers: ImportedIcebreakers
  graphqlApiUrl: string
  previewUrl: string
  canShareThread: boolean
  realIp?: string
  helpUrl?: string
  figmaAuthUrl?: string
}

function getRandomIcebreakers(icebreakers: ImportedIcebreaker[], count: number): ImportedIcebreaker[] {
  const shuffled = [...icebreakers].sort(() => 0.5 - Math.random())
  return shuffled.slice(0, count)
}

export const ChatInput = ({initialModelID}: {initialModelID?: string | null}) => {
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const {prompt, setPrompt} = useCopilotContext()
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  const suggestions = useMemo(() => {
    const randomSuggestions: ImportedIcebreaker[] = getRandomIcebreakers(data.functional, 6)
    return randomSuggestions
  }, [])

  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto'
      textareaRef.current.style.height = `${textareaRef.current.scrollHeight}px`
    }
  }, [prompt])

  const handleInputChange = (event: React.ChangeEvent<HTMLTextAreaElement>) => {
    setPrompt(event.target.value)
  }

  return (
    <div className={styles.wrapper}>
      <div className={styles.stackWrapper}>
        <div>
          <CopilotIconAnimation hidden />
        </div>
        <ul className={`${styles.suggestions} list-style-none`}>
          {suggestions.map((suggestion: ImportedIcebreaker) => (
            <li key={suggestion.id} className={styles.suggestionButton}>
              <SuggestionCard
                titleHtml={suggestion.titleHtml as SafeHTMLString}
                icon={suggestion.icon}
                color={suggestion.color}
                onClick={() => {
                  setPrompt(suggestion.message)
                  setIsDialogOpen(true)
                }}
              />
            </li>
          ))}
        </ul>
        <div className={styles.legalDisclaimer}>
          <LegalDisclaimer />
        </div>
      </div>
      <div className={styles.footer}>
        <form className={styles.container}>
          <div className={styles.inputContainer}>
            <textarea
              ref={textareaRef}
              className={styles.input}
              placeholder="Ask Copilot"
              disabled={false}
              value={prompt}
              rows={1}
              onFocus={event => event.target.setSelectionRange(0, event.target.value.length)}
              onChange={event => {
                handleInputChange(event)
                if (textareaRef.current) {
                  textareaRef.current.style.height = 'auto'
                  textareaRef.current.style.height = `${textareaRef.current.scrollHeight}px`
                }
              }}
              onKeyDown={event => {
                if (event.key === 'Enter' && !event.shiftKey) {
                  event.preventDefault()
                  if (prompt.trim() !== '') {
                    setIsDialogOpen(true)
                  }
                }
              }}
            />
          </div>
          <div className={styles.toolbar}>
            <div className={styles.toolbarLeft} />
            <div className={styles.toolbarRight}>
              <div>
                <EntitlementProvider initialLicenseType={CopilotLicenseType.Unlicensed}>
                  <ModelPicker initialModelID={initialModelID} />
                </EntitlementProvider>
              </div>
              <div className={styles.trailingActions}>
                <CommandIconButton
                  commandId="copilot-chat:send-message"
                  variant="invisible"
                  size="medium"
                  icon={PaperAirplaneIcon}
                  aria-label="Send now"
                  tooltipDirection="n"
                  onClick={() => {
                    if (prompt.trim() !== '') {
                      setIsDialogOpen(true)
                    }
                  }}
                />
              </div>
            </div>
          </div>
        </form>
      </div>
      {isDialogOpen && <SignInDialog onClose={() => setIsDialogOpen(false)} />}
    </div>
  )
}
