import {useCallback, useEffect, useMemo, useRef, useState, type CSSProperties} from 'react'
import {BookIcon, MentionIcon, PaperAirplaneIcon} from '@primer/octicons-react'
import {Avatar, Text} from '@primer/react-brand'

import {COPY} from '../CopilotExtensionsIndex.data'
import {CopilotIcon} from '../CopilotIcons/CopilotIcons'
import {validExtensions, type Extension} from './CopilotExtensionsHeroUI.types'
import useMotion from './CopilotExtensionsHeroUI.motion'
import {wait} from '../utils/time'
import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'

interface CopilotExtensionsHeroUIProps {}

const defaultProps: Partial<CopilotExtensionsHeroUIProps> = {}

const extensionIconPath = '/images/modules/site/copilot/extensions/svgs/{extension}.svg'

const EXTENSION_COLORS: Record<Extension, string> = {
  azure: '#161b22',
  datastax: '#000',
  docker: '#1e63ed',
  mongodb: '#161b22',
  sentry: '#5e4576',
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
const CopilotExtensionsHeroUI: React.FC<CopilotExtensionsHeroUIProps> = ({} = defaultProps) => {
  const [currentExtension, setCurrentExtension] = useState<Extension | ''>('')
  const [currentMessage, setCurrentMessage] = useState<string>('')
  const [isExtensionMenuOpen, setIsExtensionMenuOpen] = useState<boolean>(false)
  const wrapperRef = useRef<HTMLDivElement>(null)
  const extensionMenuRef = useRef<HTMLUListElement>(null)
  const extensionMenuToggleRef = useRef<HTMLButtonElement>(null)
  const extensionQueryFieldRef = useRef<HTMLInputElement>(null)
  const timeoutRefs = useRef<NodeJS.Timeout[]>([])

  const typeInMessage = useCallback(async (message: string) => {
    const characterArray = message.split('')
    let typedMessage = ''

    setCurrentMessage('')
    if (!message) return

    for (let i = 0; i < characterArray.length; i++) {
      typedMessage += characterArray[i]
      setCurrentMessage(typedMessage)

      timeoutRefs.current.push(await wait(50))
      if (extensionQueryFieldRef.current) {
        extensionQueryFieldRef.current.scrollLeft = extensionQueryFieldRef.current.scrollWidth
      }
    }
  }, [])

  const onExtensionClick = useCallback(
    (extension: Extension, isFromUser = true) => {
      setCurrentExtension(currentExtension === extension ? '' : extension)
      setIsExtensionMenuOpen(false)
      typeInMessage(currentExtension === extension ? '' : COPY.hero.ui.extensions[extension].messagePlaceholder)
      if (isFromUser) extensionQueryFieldRef.current?.focus()
    },
    [currentExtension, typeInMessage],
  )

  const {showExtensionMenu} = useMotion({wrapperRef, extensionMenuRef, setIsExtensionMenuOpen, onExtensionClick})

  const {isIntersecting: isInView} = useIntersectionObserver(wrapperRef, {
    threshold: 0.75,
    isOnce: true,
  })

  const currentPlaceholder = useMemo(
    () =>
      currentExtension ? COPY.hero.ui.extensions[currentExtension].messagePlaceholder : COPY.hero.ui.messagePlaceholder,
    [currentExtension],
  )

  const extensionMenuDOM = useMemo(() => {
    return (
      <ul
        className={`lp-HeroUI-extensionMenu${isExtensionMenuOpen ? ' isOpen' : ''}`}
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
              <div style={{'--background-color': EXTENSION_COLORS[extension]} as CSSProperties}>
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
  }, [currentExtension, isExtensionMenuOpen, onExtensionClick])

  useEffect(() => {
    const checkIfClickedOutside = (event: Event) => {
      const isToggle = getEventPath(event).includes(extensionMenuToggleRef.current as EventTarget)
      if (isToggle) return

      const isInsideMenu = getEventPath(event).includes(extensionMenuRef.current as EventTarget)
      if (!isInsideMenu) setIsExtensionMenuOpen(false)
    }

    if (isExtensionMenuOpen) {
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-event-listener
      document.addEventListener('click', checkIfClickedOutside)
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-event-listener
      document.addEventListener('touchstart', checkIfClickedOutside, {passive: true})
    } else {
      document.removeEventListener('click', checkIfClickedOutside)
      document.removeEventListener('touchstart', checkIfClickedOutside)
    }
  }, [isExtensionMenuOpen])

  useEffect(() => {
    if (isInView) {
      showExtensionMenu()
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isInView])

  useEffect(() => {
    return () => {
      if (timeoutRefs.current) {
        // eslint-disable-next-line react-compiler/react-compiler
        // eslint-disable-next-line react-hooks/exhaustive-deps
        for (const timeoutRef of timeoutRefs.current) {
          clearTimeout(timeoutRef)
        }
      }
    }
  }, [])

  return (
    <div ref={wrapperRef} className="lp-HeroUI">
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
                  onClick={() => {
                    setIsExtensionMenuOpen(!isExtensionMenuOpen)
                  }}
                  onKeyDown={event => {
                    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                    if (event.key === 'Escape') {
                      setIsExtensionMenuOpen(false)
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
    </div>
  )
}

CopilotExtensionsHeroUI.displayName = 'CopilotExtensionsHeroUI'

export default CopilotExtensionsHeroUI
