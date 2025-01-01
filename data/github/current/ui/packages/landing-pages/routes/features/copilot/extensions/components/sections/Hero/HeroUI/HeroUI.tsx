import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {BookIcon, MentionIcon, PaperAirplaneIcon} from '@primer/octicons-react'
import {Avatar, Text} from '@primer/react-brand'

import {COPY} from '../../../../Index.data'
import {CopilotIcon} from '../../../CopilotIcons/CopilotIcons'
import {validExtensions, type Extension} from './HeroUI.types'
import useMotion from './HeroUI.motion'
import PlayButton from '../../../PlayButton/PlayButton'
import {wait} from '../../../../utils/time'
import useIntersectionObserver from '../../../../../../../../lib/hooks/useIntersectionObserver'
import {checkPrefersReducedMotion} from '../../../../../../../../lib/utils/platform'

interface HeroUIProps {}

const defaultProps: Partial<HeroUIProps> = {}

const extensionIconPath = '/images/modules/site/copilot/extensions/hero-ui/{extension}.svg'

const EXTENSION_COLORS: Record<Extension, string> = {
  docker: '#1E63EE',
  mermaidchart: '#E0095F',
  models: '#3A1B81',
  perplexityai: '#F3F3EE',
  sentry: '#5E4576',
}

const getEventPath = (event: Event) => {
  const path: EventTarget[] = []
  let currentElem: HTMLElement | null = event.target as HTMLElement

  while (currentElem) {
    path.push(currentElem)
    currentElem = currentElem.parentElement
  }

  if (!path.includes(window) && !path.includes(document)) path.push(document)
  if (!path.includes(window)) path.push(window)

  return path
}

// eslint-disable-next-line no-empty-pattern
const HeroUI: React.FC<HeroUIProps> = ({} = defaultProps) => {
  const [isMounted, setIsMounted] = useState<boolean>(false)
  const [shouldReduceMotion, setShouldReduceMotion] = useState<boolean>(false)
  const [currentExtension, setCurrentExtension] = useState<Extension | ''>('')
  const [currentMessage, setCurrentMessage] = useState<string>('')
  const [isExtensionMenuOpen, setIsExtensionMenuOpen] = useState<boolean>(false)
  const [isManualMode, setIsManualMode] = useState(false)

  const wrapperRef = useRef<HTMLDivElement>(null)
  const extensionMenuRef = useRef<HTMLUListElement>(null)
  const extensionMenuToggleRef = useRef<HTMLButtonElement>(null)
  const extensionQueryFieldRef = useRef<HTMLInputElement>(null)
  const timeoutRefs = useRef<NodeJS.Timeout[]>([])
  const isAnimationPausedRef = useRef(false)
  const isManualModeRef = useRef(false)

  const typeInMessage = useCallback(async (message: string) => {
    const abortController = new AbortController()
    const signal = abortController.signal

    try {
      // Clear any existing timeouts to stop current typing
      if (timeoutRefs.current.length) {
        for (const timeout of timeoutRefs.current) clearTimeout(timeout)
        timeoutRefs.current = []
      }

      if (!message) {
        setCurrentMessage('')
        return
      }

      // Start new typing animation
      const characterArray = message.split('')
      let typedMessage = ''
      setCurrentMessage('')

      for (let i = 0; i < characterArray.length; i++) {
        if (signal.aborted) return

        typedMessage += characterArray[i]
        setCurrentMessage(typedMessage)

        if (!isAnimationPausedRef.current || isManualModeRef.current) timeoutRefs.current.push(await wait(50))
        if (extensionQueryFieldRef.current) {
          extensionQueryFieldRef.current.scrollLeft = extensionQueryFieldRef.current.scrollWidth
        }
      }
    } finally {
      abortController.abort()
    }
  }, [])

  const onExtensionClick = useCallback(
    (extension: Extension, isFromUser = true) => {
      setCurrentExtension(extension)
      setIsExtensionMenuOpen(false)
      typeInMessage(COPY.hero.ui.extensions[extension].messagePlaceholder)
      if (isFromUser) extensionQueryFieldRef.current?.focus()
    },
    [typeInMessage],
  )

  const {showExtensionMenu} = useMotion({
    wrapperRef,
    extensionMenuRef,
    setIsExtensionMenuOpen,
    onExtensionClick,
    isAnimationPausedRef,
    isManualModeRef,
  })

  const updateIsAnimationPaused = useCallback((newState: boolean) => {
    isAnimationPausedRef.current = newState

    // Update UI
    const pauseButton = document.querySelector('.js-heroui-pause-button') as HTMLElement
    if (newState) {
      pauseButton?.classList.add('isPaused')
    } else {
      pauseButton?.classList.remove('isPaused')
    }
  }, [])

  const updateManualMode = useCallback((newState: boolean) => {
    isManualModeRef.current = newState
    setIsManualMode(newState)
  }, [])

  type AnimationAction = {type: 'PLAY'} | {type: 'PAUSE'} | {type: 'TOGGLE'} | {type: 'MANUAL'}

  const switchState = useCallback(
    (action: AnimationAction) => {
      switch (action.type) {
        case 'PLAY':
          updateIsAnimationPaused(false)
          showExtensionMenu()
          break

        case 'PAUSE':
          updateIsAnimationPaused(true)
          break

        case 'TOGGLE':
          updateManualMode(false)
          updateIsAnimationPaused(!isAnimationPausedRef.current)

          if (!isAnimationPausedRef.current) {
            showExtensionMenu()
          }
          break

        case 'MANUAL':
          updateManualMode(true)
          updateIsAnimationPaused(true)

          if (!isExtensionMenuOpen) {
            setIsExtensionMenuOpen(true)
          }
          break

        default:
        // console.warn('Unknown action type:', action)
      }
    },
    [isExtensionMenuOpen, showExtensionMenu, updateIsAnimationPaused, updateManualMode],
  )

  const onExtensionMenuTogglelick = useCallback(() => {
    if (!isManualModeRef.current) {
      switchState({type: 'MANUAL'})
    } else {
      setIsExtensionMenuOpen(!isExtensionMenuOpen)
    }
  }, [isExtensionMenuOpen, switchState])

  const {isIntersecting: isInView} = useIntersectionObserver(wrapperRef, {
    threshold: 0.75,
    isOnce: false,
  })

  const currentPlaceholder = useMemo(
    () =>
      currentExtension ? COPY.hero.ui.extensions[currentExtension].messagePlaceholder : COPY.hero.ui.messagePlaceholder,
    [currentExtension],
  )

  const extensionMenuDOM = useMemo(() => {
    return (
      <ul
        className={`lp-HeroUI-extensionMenu
          ${isManualMode ? ' isManualMode' : ''}
          ${isExtensionMenuOpen ? ' isOpen' : ''}
        `}
        ref={extensionMenuRef}
        aria-label={COPY.hero.ui.aria.menu}
        aria-hidden={!isExtensionMenuOpen}
        id="extension-menu"
        role="listbox"
      >
        {validExtensions.map(extension => {
          return (
            <li
              key={extension}
              role="option"
              aria-selected={currentExtension === extension}
              onClick={() => onExtensionClick(extension)}
              onKeyDown={event => {
                // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                if (event.key === 'Enter') {
                  event.preventDefault()
                  onExtensionClick(extension)
                  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                } else if (event.key === 'Escape') {
                  setIsExtensionMenuOpen(false)
                  extensionMenuToggleRef.current?.focus()
                }
              }}
              tabIndex={isExtensionMenuOpen ? 0 : -1}
            >
              <div style={{'--background-color': EXTENSION_COLORS[extension]}}>
                <Avatar size={32} src={extensionIconPath.replace('{extension}', extension)} alt="" />
              </div>
              <Text className="lp-HeroUI-text" weight="semibold">
                {COPY.hero.ui.extensions[extension].name}
              </Text>
              <Text className="lp-HeroUI-text" weight="light" size="100">
                @{COPY.hero.ui.extensions[extension].handle}
              </Text>
            </li>
          )
        })}

        {/* focus trap */}
        <li
          role="option"
          tabIndex={isExtensionMenuOpen ? 0 : -1}
          style={{position: 'absolute', left: '-9999px'}}
          onFocus={() => {
            extensionMenuToggleRef.current?.focus()
          }}
          aria-selected={false}
        />
      </ul>
    )
  }, [currentExtension, isExtensionMenuOpen, isManualMode, onExtensionClick])

  useEffect(() => {
    const checkIfClickedOutside = (event: Event) => {
      const isToggle = getEventPath(event).includes(extensionMenuToggleRef.current as EventTarget)
      if (isToggle) return

      const clickedButton = (event.target as HTMLElement).closest('button.js-heroui-pause-button')
      if (clickedButton) return

      const isInsideMenu = getEventPath(event).includes(extensionMenuRef.current as EventTarget)
      if (!isInsideMenu) setIsExtensionMenuOpen(false)
    }

    if (isExtensionMenuOpen && isManualModeRef.current) {
      document.addEventListener('click', checkIfClickedOutside)
      document.addEventListener('touchstart', checkIfClickedOutside, {passive: true})

      return () => {
        document.removeEventListener('click', checkIfClickedOutside)
        document.removeEventListener('touchstart', checkIfClickedOutside)
      }
    }
  }, [isExtensionMenuOpen])

  // Play/Pause button
  useEffect(() => {
    const pauseButton = document.querySelector('.js-heroui-pause-button') as HTMLElement

    const handleClick = () => {
      switchState({type: 'TOGGLE'})
    }

    pauseButton?.addEventListener('click', handleClick)
    return () => {
      pauseButton?.removeEventListener('click', handleClick)
    }
  }, [switchState])

  useEffect(() => {
    if (isInView && !shouldReduceMotion) {
      switchState({type: 'PLAY'})
    } else {
      switchState({type: 'PAUSE'})
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isInView])

  useEffect(() => {
    if (!isMounted) return
    setShouldReduceMotion(checkPrefersReducedMotion())
  }, [isMounted])

  useEffect(() => {
    setIsMounted(true)

    return () => {
      if (timeoutRefs.current) {
        for (const timeoutRef of timeoutRefs.current) {
          clearTimeout(timeoutRef)
        }
      }
    }
  }, [])

  return (
    <div ref={wrapperRef} className="lp-HeroUI">
      <div className="sr-only">{COPY.hero.ui.aria.description}</div>
      <div className="lp-HeroUI-content">
        <div className="lp-HeroUI-windowBar">
          <div>
            <CopilotIcon />
          </div>
          <Text className="lp-HeroUI-text" weight="semibold">
            {COPY.hero.ui.windowTitle}
          </Text>
        </div>

        <div className="lp-HeroUI-chat">
          <div>
            <CopilotIcon ariaLabel={COPY.hero.ui.aria.copilotLogo} />
            <Text className="lp-HeroUI-text" size="400" weight="semibold">
              {COPY.hero.ui.chatTitle}
            </Text>
            <div>
              <Text className="lp-HeroUI-text" weight="medium">
                {COPY.hero.ui.chatWelcome.greeting}
              </Text>{' '}
              <Text className="lp-HeroUI-text" weight="light">
                {COPY.hero.ui.chatWelcome.question}
              </Text>
            </div>
          </div>
        </div>

        <div className="lp-HeroUI-message">
          <div className="lp-HeroUI-message-text">
            {currentExtension && (
              <Text className="lp-HeroUI-message-text-handle">@{COPY.hero.ui.extensions[currentExtension].handle}</Text>
            )}

            <input
              ref={extensionQueryFieldRef}
              className="lp-HeroUI-message-text-input"
              placeholder={currentPlaceholder}
              value={currentMessage}
              readOnly
            />
          </div>

          <div className="lp-HeroUI-message-toolbar">
            <div>
              <div className="lp-HeroUI-message-toolbar-icon">
                <BookIcon />
              </div>
              <div>
                <button
                  ref={extensionMenuToggleRef}
                  aria-expanded={isExtensionMenuOpen}
                  aria-haspopup="listbox"
                  aria-controls="extension-menu"
                  className={`lp-HeroUI-message-toolbar-icon lp-HeroUI-message-toolbar-icon--mention${
                    currentExtension ? ' isActive' : ''
                  }`}
                  onClick={() => onExtensionMenuTogglelick()}
                  onKeyDown={event => {
                    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                    if (event.key === 'Escape') {
                      setIsExtensionMenuOpen(false)
                      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                    } else if (event.key === 'Enter' || event.key === ' ') {
                      onExtensionMenuTogglelick()
                      if (!isExtensionMenuOpen) {
                        const firstMenuItem = extensionMenuRef.current?.querySelector(
                          'li[role="option"]',
                        ) as HTMLElement
                        // A11y: Move focus to first item when opening menu
                        firstMenuItem?.focus()
                      }
                    }
                  }}
                  aria-label={COPY.hero.ui.aria.mention}
                >
                  <MentionIcon />
                </button>
                {extensionMenuDOM}
              </div>
            </div>

            <div>
              <div className="lp-HeroUI-message-toolbar-icon">
                <PaperAirplaneIcon />
              </div>
            </div>
          </div>
        </div>
      </div>

      {!shouldReduceMotion && (
        <div className="lp-HeroUI-pauseButtonContainer">
          <PlayButton scene="heroUI" ariaLabels={COPY.aria.togglePlayButton} />
        </div>
      )}
    </div>
  )
}

HeroUI.displayName = 'HeroUI'

export default HeroUI
