import type {Icebreaker} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {PaperAirplaneIcon, SparkleFillIcon} from '@primer/octicons-react'
import {Heading, Stack, TextInput} from '@primer/react'
import {useEffect, useState} from 'react'

import type {SparkPayload} from '../routes/payloads'
import styles from './Layout.module.css'
import SparksList from './SparksList'
import {SuggestionCard} from './SuggestionCard'

type IcebreakerType = 'functional' | 'instructional' | 'interactional'

interface IcebreakerData {
  type: IcebreakerType
  data: Icebreaker[]
}

function isIcebreakerDataArray(value: unknown): value is IcebreakerData[] {
  return Array.isArray(value) && value.every(item => 'type' in item && 'data' in item)
}

const Layout: React.FC = () => {
  const {icebreakers} = useAppPayload<SparkPayload>()
  const [suggestions, setSuggestions] = useState<Icebreaker[]>()
  const [promptText, setPromptText] = useState('')

  useEffect(() => {
    if (isIcebreakerDataArray(icebreakers)) {
      const functionalIcebreakers = icebreakers.find(ib => ib.type === 'functional')
      if (functionalIcebreakers && functionalIcebreakers.data.length > 0) {
        setSuggestions(functionalIcebreakers.data)
      }
    }
  }, [icebreakers])

  const getPromptURL = (text: string) => {
    const url = new URL(window.location.href, window.location.origin)
    url.pathname = '/copilot/spark'
    url.searchParams.set('initialPrompt', text)
    return url.toString()
  }

  return (
    <div className={styles.container} data-testid="dashboard-layout" data-hpc>
      <div className={styles.main}>
        <div className={styles.content}>
          <div className={styles.innerContent}>
            <Stack direction="vertical" align="center" padding="normal">
              <SparkleFillIcon size={40} className="fgColor-done" />
              <Heading as="h1">GitHub Spark</Heading>
              <p className="fgColor-muted text-wrap-balance">Generate, refine and deploy apps, customized for you.</p>
              <div className={styles.formContainer}>
                <TextInput
                  autoFocus
                  className={styles.promptInputContainer}
                  placeholder="What do you want to create?"
                  value={promptText}
                  onChange={e => setPromptText(e.target.value)}
                  onKeyDown={(keyboardEvent: React.KeyboardEvent) => {
                    if (keyboardEvent.code === 'Enter' || keyboardEvent.code === 'NumpadEnter') {
                      window.location.href = getPromptURL(promptText)
                    }
                  }}
                  trailingAction={
                    <TextInput.Action
                      onClick={() => {
                        window.location.href = getPromptURL(promptText)
                      }}
                      icon={PaperAirplaneIcon}
                      aria-label="Submit prompt"
                      data-testid="submit-prompt"
                      tooltipDirection="n"
                    />
                  }
                />
              </div>
              <Stack direction="horizontal" wrap="wrap" gap="condensed" align="center">
                {suggestions &&
                  suggestions.map((suggestion: Icebreaker) => (
                    <SuggestionCard
                      key={suggestion.id}
                      titleHtml={suggestion.titleHtml as SafeHTMLString}
                      icon={suggestion.icon}
                      color={suggestion.color}
                      onClick={() => {
                        window.location.href = getPromptURL(suggestion.message)
                      }}
                    />
                  ))}
              </Stack>
            </Stack>
            <SparksList />
          </div>
        </div>
      </div>
    </div>
  )
}

export default Layout
