import {useEffect, useRef, useState} from 'react'
import type {LanguageTocItem} from './types'

import {ActionList, ActionMenu} from '@primer/react'
import {testIdProps} from '@github-ui/test-id-props'

import CodespacesSuggestion from './CodespacesSuggestion'
import MarkdownContent from './MarkdownContent'
import type {SafeHTMLString} from '@github-ui/safe-html'

import {ModelLegalTerms} from '../../../../components/ModelLegalTerms'
import type {GettingStarted} from '../../../../types'
import {
  getDefaultUiState,
  setLocalStorageUiState,
  type ModelPersistentUIState,
} from '../../../../utils/playground-local-storage'
import styles from './CodeContainer.module.css'

export function CodeContainer({
  openInCodespaceUrl,
  showCodespacesSuggestion,
  gettingStarted,
  modelName,
  uiState,
  setUiState,
}: {
  openInCodespaceUrl: string
  showCodespacesSuggestion: boolean
  gettingStarted: GettingStarted
  modelName: string
  uiState?: ModelPersistentUIState // playground view only
  setUiState?: (uiState: ModelPersistentUIState) => void // playground view only
}) {
  const defaultUiState = getDefaultUiState(gettingStarted, uiState?.preferredLanguage, uiState?.preferredSdk)

  const [selectedLanguage, setSelectedLanguage] = useState(defaultUiState.preferredLanguage)

  const [selectedSDK, setSelectedSDK] = useState(defaultUiState.preferredSdk)

  const languageEntry = selectedLanguage ? gettingStarted[selectedLanguage] : null
  const sdkEntry =
    languageEntry && selectedSDK && languageEntry.sdks[selectedSDK] ? languageEntry.sdks[selectedSDK] : null

  const [currentHeading, setCurrentHeading] = useState<string | null>(null)

  const contentRef = useRef<HTMLDivElement>(null)
  const contentWrapperRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const wrapperElement = contentWrapperRef.current
    if (!wrapperElement || !sdkEntry) return

    const anchors = sdkEntry.tocHeadings.filter(heading => heading.level === 2).map(heading => heading.anchor)
    const options = {root: wrapperElement, rootMargin: '0px', threshold: 0.5}
    const callback = (entries: IntersectionObserverEntry[]) => {
      for (const entry of entries) {
        const id = entry.target.id
        if (entry.isIntersecting) {
          setCurrentHeading(id)
        }
      }
    }
    const observer = new IntersectionObserver(callback, options)

    for (const anchor of anchors) {
      const el = wrapperElement.querySelector(`#user-content-${anchor}`)
      if (el) observer.observe(el)
    }

    return () => {
      for (const anchor of anchors) {
        const el = wrapperElement?.querySelector(`#user-content-${anchor}`)
        if (el) {
          observer.unobserve(el)
        }
      }
    }
  }, [sdkEntry])

  if (!languageEntry || !sdkEntry || !selectedLanguage || !selectedSDK) {
    return <p {...testIdProps('code-container')}>Error</p>
  }

  const {tocHeadings, content} = sdkEntry

  // Construct a language options dropdown that includes the current SDK in the link, if possible
  const languageToc = Object.entries(gettingStarted).map(([key, language]) => {
    return {key, active: language.name === languageEntry.name, name: language.name} as LanguageTocItem
  })

  const levelTwoTitles = tocHeadings.filter(heading => heading.level === 2)

  const scrollToAnchor = (anchor: string) => {
    if (contentRef.current === null) return
    const element = contentRef.current.querySelector(`#user-content-${anchor}`)
    element?.parentElement?.querySelector('h2')?.focus()
    element?.scrollIntoView({block: 'start', behavior: 'smooth'})
  }

  const handleSelectLanguage = (key: string) => {
    const newLanugageEntry = gettingStarted[key]
    if (!newLanugageEntry || !selectedSDK) return
    // Reset SDK selection
    const firstSDK = Object.keys(newLanugageEntry.sdks).includes(selectedSDK)
      ? selectedSDK
      : Object.keys(newLanugageEntry.sdks)[0] || null

    setSelectedLanguage(key)

    const newUiState = {
      ...defaultUiState,
      preferredLanguage: key,
      ...(firstSDK && {preferredSdk: firstSDK}),
    }

    setLocalStorageUiState(newUiState)

    if (firstSDK) setSelectedSDK(firstSDK)
    if (setUiState && uiState) {
      setUiState({...uiState, preferredLanguage: key, preferredSdk: firstSDK || selectedSDK})
    }
  }

  const handleSelectSDK = (sdk: string) => {
    const newUiState = {
      ...defaultUiState,
      preferredLanguage: selectedLanguage,
      preferredSdk: sdk,
    }

    setLocalStorageUiState(newUiState)
    setSelectedSDK(sdk)
    if (setUiState && uiState) {
      setUiState({...uiState, preferredLanguage: selectedLanguage, preferredSdk: sdk})
    }
  }

  return (
    <div className={styles.outerCodeContainer} {...testIdProps('code-container')}>
      <div className={styles.innerCodeContainer}>
        <div className={styles.menuWrapper}>
          <ActionMenu>
            <ActionMenu.Button alignContent="start" block>
              <span className="color-fg-muted">Language: </span>
              {languageEntry.name}
            </ActionMenu.Button>
            <ActionMenu.Overlay width="small">
              <ActionList selectionVariant="single">
                {languageToc.map(({key, name}) => (
                  <ActionList.Item
                    key={key}
                    selected={name === languageEntry.name}
                    aria-label={`Language: ${name}`}
                    onSelect={() => handleSelectLanguage(key)}
                  >
                    {name}
                  </ActionList.Item>
                ))}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
          <ActionMenu>
            <ActionMenu.Button block alignContent="start">
              <span className="color-fg-muted">SDK: </span>
              {sdkEntry.name}
            </ActionMenu.Button>
            <ActionMenu.Overlay width="small">
              <ActionList selectionVariant="single">
                {Object.entries(languageEntry.sdks).map(([key, sdk]) => (
                  <ActionList.Item
                    key={key}
                    selected={sdk.name === sdkEntry.name}
                    aria-label={`SDK: ${sdk.name}`}
                    onSelect={() => handleSelectSDK(key)}
                  >
                    {sdk.name}
                  </ActionList.Item>
                ))}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </div>
        <div className={styles.chaptersSection}>
          <ActionList>
            <ActionList.Group>
              <ActionList.GroupHeading as="h2">Chapters</ActionList.GroupHeading>
              {levelTwoTitles.map(heading => {
                const selected = currentHeading === `user-content-${heading.anchor}`
                return (
                  <ActionList.Item
                    key={heading.anchor}
                    onSelect={() => scrollToAnchor(heading.anchor)}
                    active={selected}
                    aria-current={selected}
                  >
                    {heading.text}
                  </ActionList.Item>
                )
              })}
            </ActionList.Group>
          </ActionList>
        </div>
        <div className={styles.codespaceSuggestionWrapper}>
          {showCodespacesSuggestion && <CodespacesSuggestion openInCodespaceUrl={openInCodespaceUrl} />}
        </div>
      </div>
      <div className={styles.contentWrapper} ref={contentWrapperRef}>
        <MarkdownContent payload={content as SafeHTMLString} ref={contentRef} />
        <ModelLegalTerms modelName={modelName} />
      </div>
    </div>
  )
}
