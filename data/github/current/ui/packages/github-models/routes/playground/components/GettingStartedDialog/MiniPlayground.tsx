import styles from './ModelLayout.module.css'
import {useCallback, useEffect, useState, useRef, useMemo} from 'react'
import {Text, Box, FormControl, IconButton, Textarea, useResponsiveValue} from '@primer/react'
import {PaperAirplaneIcon} from '@primer/octicons-react'
import type {ModelInputSchema} from '../../../../types'
import type {Model} from '@github-ui/marketplace-common'
import {ModelLegalTerms} from './ModelLegalTerms'
import {ModelUrlHelper} from '../../../../utils/model-url-helper'
import {PlaygroundCard} from './PlaygroundCard'

export function MiniPlayground({model, modelInputSchema}: {model: Model; modelInputSchema: ModelInputSchema}) {
  const [text, setText] = useState('')
  const hasText = text.length > 0
  const isMobile = useResponsiveValue({narrow: true}, false)

  const miniPlaygroundRef = useRef<HTMLFormElement>(null)
  const miniPlaygroundInputRef = useRef<HTMLTextAreaElement>(null)
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
    return samplesWithContent[Math.floor(Math.random() * samplesWithContent?.length)]
  }, [samplesWithContent])
  const suggestedPrompts = isMobile ? [randomPrompt] : samplesWithContent?.slice(0, SUGGESTION_DISPLAY_MAX)

  const handlePlaygroundCardClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (e.currentTarget.parentNode instanceof HTMLFormElement) {
      e.currentTarget.parentNode.submit()
    }
  }

  const handleKeyDown = async (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
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

  const playgroundURL = ModelUrlHelper.playgroundUrl(model)

  return (
    <>
      <Text
        sx={{
          fontWeight: 'bold',
          display: ['block', 'block', 'none'],
          mb: 2,
        }}
      >
        Try {model.friendly_name}
      </Text>
      <Box as="form" sx={{mb: 3, pt: 1, position: 'relative'}} action={playgroundURL} ref={miniPlaygroundRef}>
        <FormControl id="miniplayground_icebreaker">
          <FormControl.Label visuallyHidden>Mini Playground Prompt Input</FormControl.Label>
          <Textarea
            name="p"
            ref={miniPlaygroundInputRef}
            value={text}
            onChange={e => setText(e.target.value)}
            onKeyDown={handleKeyDown}
            rows={1}
            placeholder={`Enter a message...`}
            resize="none"
            block
            sx={{pr: 5}}
          />

          <IconButton
            icon={PaperAirplaneIcon}
            variant="invisible"
            aria-label="Submit message"
            onClick={() => miniPlaygroundRef.current?.submit()}
            sx={{
              position: 'absolute',
              right: 0,
              mr: 2,
              // center vertically
              top: '50%',
              marginTop: '-14px',
            }}
          />
        </FormControl>
      </Box>
      <Box sx={{pb: 3}}>
        <Box sx={{position: 'relative'}} className={styles.animateHeight} ref={animationContainerRef}>
          <Box
            sx={{position: 'absolute', top: 0}}
            ref={legalContainerRef}
            className={`${styles.fadeInOut} ${hasText ? styles.fadeInOutShow : ''}`}
          >
            <Box sx={{marginTop: '-2px'}}>
              <ModelLegalTerms modelName={model.name} />
            </Box>
          </Box>

          {suggestedPrompts && (
            <Box
              ref={icebreakerContainerRef}
              className={`${styles.fadeInOut} ${hasText ? '' : styles.fadeInOutShow}`}
              sx={{
                position: 'relative', // necessary for z-index to work
                display: 'grid',
                gridTemplateColumns: ['1fr', '1fr', '1fr 1fr', Array(suggestedPrompts.length).fill('1fr').join(' ')],
                gap: 3,
              }}
            >
              {suggestedPrompts.map(sample => {
                if (sample) {
                  // random value is memoized and can be null on first render
                  return (
                    <Box as="form" sx={{display: 'flex'}} key={sample} action={playgroundURL}>
                      <input type="hidden" value={sample} name="p" />
                      <PlaygroundCard sample={sample} onClick={handlePlaygroundCardClick} />
                    </Box>
                  )
                }
              })}
            </Box>
          )}
        </Box>
      </Box>
    </>
  )
}
