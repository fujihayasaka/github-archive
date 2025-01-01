import styles from './MiniPlayground.module.css'
import {useCallback, useEffect, useState, useRef, useMemo} from 'react'
import {TextInput} from '@primer/react'
import {PaperAirplaneIcon} from '@primer/octicons-react'
import {modelPlaygroundPath} from '@github-ui/paths'
import type {ModelInputSchema} from '../../../types'
import type {Model} from '@github-ui/marketplace-common'
import {ModelLegalTerms} from '../../../components/ModelLegalTerms'
import {PlaygroundCard} from '../../../components/PlaygroundCard'

export function MiniPlayground({
  model,
  modelInputSchema,
  isMobile,
}: {
  model: Model
  modelInputSchema: ModelInputSchema
  isMobile: boolean
}) {
  const [text, setText] = useState('')
  const hasText = text.length > 0

  const miniPlaygroundRef = useRef<HTMLFormElement>(null)
  const legalContainerRef = useRef<HTMLDivElement>(null)
  const icebreakerContainerRef = useRef<HTMLDivElement>(null)
  const animationContainerRef = useRef<HTMLDivElement>(null)

  const samplesToContent = modelInputSchema?.sampleInputs?.map(input => {
    const firstMessageWithContent = input.messages?.find(message => message.content)
    return firstMessageWithContent?.content
  })

  const samplesWithContent = useMemo(() => {
    return samplesToContent?.filter(sample => sample !== undefined) || []
  }, [samplesToContent])
  const SUGGESTION_DISPLAY_MAX = 4
  // If mobile, we only show one, so pick one at random
  const randomPrompt = useMemo(() => {
    const sample = samplesWithContent[Math.floor(Math.random() * samplesWithContent?.length)]
    return sample ? [sample] : []
  }, [samplesWithContent])
  const suggestedPrompts = isMobile ? randomPrompt : samplesWithContent?.slice(0, SUGGESTION_DISPLAY_MAX)

  const handlePlaygroundCardOnAction = (e: React.MouseEvent<HTMLDivElement> | React.KeyboardEvent<HTMLDivElement>) => {
    if (e.currentTarget.parentNode instanceof HTMLFormElement) {
      e.currentTarget.parentNode.submit()
    }
  }

  const handleKeyDown = async (e: React.KeyboardEvent<HTMLInputElement>) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (e.key === 'Escape') {
      e.preventDefault()
      setText('')
    }

    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    else if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.nativeEvent.isComposing) {
      const form = miniPlaygroundRef.current
      if (form) {
        e.preventDefault()
        form.submit()
      }
    }
  }

  const adjustHeights = useCallback(() => {
    if (animationContainerRef.current && legalContainerRef.current && icebreakerContainerRef.current) {
      animationContainerRef.current.style.height = hasText
        ? `${legalContainerRef.current.offsetHeight}px`
        : `${icebreakerContainerRef.current.offsetHeight}px`
    }
  }, [hasText])

  useEffect(() => {
    adjustHeights()
  }, [hasText, adjustHeights])

  useEffect(() => {
    const observer = new ResizeObserver(adjustHeights)
    if (legalContainerRef.current) observer.observe(legalContainerRef.current)
    if (icebreakerContainerRef.current) observer.observe(icebreakerContainerRef.current)

    return () => {
      observer.disconnect()
    }
  }, [adjustHeights])

  const playgroundURL = modelPlaygroundPath(model)

  return (
    <>
      {isMobile && <div className="text-bold mb-2">Try {model.friendly_name}</div>}
      <form action={playgroundURL} ref={miniPlaygroundRef}>
        <TextInput
          name="prompt"
          className="width-full mb-3 mt-1"
          placeholder="Enter a message..."
          onChange={e => setText(e.target.value)}
          trailingAction={<TextInput.Action icon={PaperAirplaneIcon} aria-label="Submit message" type="submit" />}
          size="large"
          aria-label="Mini Playground Prompt Input"
          onKeyDown={handleKeyDown}
        />
      </form>

      <div className={`mb-3 position-relative ${styles.animateHeight}`} ref={animationContainerRef}>
        <div
          ref={legalContainerRef}
          className={`${styles.fadeInOut} ${hasText && styles.fadeInOutShow} position-absolute left-0 right-0 top-0`}
        >
          {hasText && <ModelLegalTerms modelName={model.name} />}
        </div>
        {suggestedPrompts && (
          <div
            className={`${styles.icebreakerContainer} ${styles.fadeInOut} ${!hasText && styles.fadeInOutShow} `}
            ref={icebreakerContainerRef}
          >
            {!hasText &&
              suggestedPrompts.map(sample => (
                <form key={sample} action={playgroundURL}>
                  <input type="hidden" value={sample} name="prompt" />
                  <PlaygroundCard sample={sample} onAction={handlePlaygroundCardOnAction} />
                </form>
              ))}
          </div>
        )}
      </div>
    </>
  )
}
