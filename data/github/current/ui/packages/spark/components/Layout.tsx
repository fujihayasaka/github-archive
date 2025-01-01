import type {Icebreaker} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {isMobile} from '@github-ui/get-os'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useUserPromptContext} from '@github-ui/workbench/contexts/UserPromptContext'
import {useWorkbenchStore} from '@github-ui/workbench/contexts/WorkbenchStoreContext'
import {useBannerState} from '@github-ui/workbench/hooks/use-banner-state'
import {ACCEPTED_BASE64_IMAGE_FILE_MIME_TYPES} from '@github-ui/workbench/utilities/accepted-image-types'
import {BannerType} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import {
  HistoryIcon,
  ImageIcon,
  PaperAirplaneIcon,
  PaperclipIcon,
  SparkleFillIcon,
  StarIcon,
  XIcon,
} from '@primer/octicons-react'
import {Button, Heading, IconButton, Stack, Textarea, UnderlineNav} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef, useState} from 'react'
import {useNavigate} from 'react-router-dom'

import {useSparkUrls} from '../hooks/use-spark-urls'
import {useWorkbenchesQuery} from '../hooks/use-workbenches-query'
import type {SparkPayload} from '../routes/payloads'
import {Banner as SparkBanner} from './Banner'
import styles from './Layout.module.css'
import {LegalDisclaimer} from './LegalDisclaimer'
import {SparksList} from './SparksList'
import {SuggestionCard} from './SuggestionCard'
import {WorkbenchBanner} from './WorkbenchBanner'

type IcebreakerType = 'functional' | 'instructional' | 'interactional'

interface IcebreakerData {
  type: IcebreakerType
  data: Icebreaker[]
}

export const SparkTabs = {
  Recent: 'recent',
  Favorites: 'favorites',
  Featured: 'featured',
} as const

function isIcebreakerDataArray(value: unknown): value is IcebreakerData[] {
  return Array.isArray(value) && value.every(item => 'type' in item && 'data' in item)
}

function getRandomIcebreakers(icebreakers: Icebreaker[], count: number): Icebreaker[] {
  const shuffled = icebreakers.sort(() => 0.5 - Math.random())
  return shuffled.slice(0, count)
}

const Layout: React.FC = () => {
  const banner = useBannerState()
  const {icebreakers} = useAppPayload<SparkPayload>()

  const [suggestions, setSuggestions] = useState<Icebreaker[]>([])
  const {
    promptText,
    setPromptText,
    attachImage,
    promptImage,
    clearImageAttachment,
    imageUploadError,
    setImageUploadError,
  } = useUserPromptContext()
  const [isSubmittable, setIsSubmittable] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [selectedTab, setSelectedTab] = useState<keyof typeof SparkTabs>('Recent')
  const promptInputRef = useRef<HTMLTextAreaElement>(null)
  const textAreaScrollContainer = useRef<HTMLDivElement>(null)
  const imagesInputRef = useRef<HTMLInputElement>(null)
  const attachImageButtonRef = useRef<HTMLButtonElement>(null)
  const imageUploadErrorRef = useRef<HTMLDivElement>(null)
  const {showUrl} = useSparkUrls()
  const navigate = useNavigate()

  const workbenchStore = useWorkbenchStore()

  const MIN_HEIGHT = 120
  const MAX_HEIGHT = 300

  useEffect(() => {
    if (isIcebreakerDataArray(icebreakers)) {
      const functionalIcebreakers = icebreakers.find(ib => ib.type === 'functional')
      if (functionalIcebreakers && functionalIcebreakers.data.length > 0) {
        setSuggestions(getRandomIcebreakers(functionalIcebreakers.data, 3))
      }
    }
  }, [icebreakers])

  useLayoutEffect(() => {
    let tries = 0

    function adjustHeight() {
      if (!promptInputRef.current || !textAreaScrollContainer.current) return

      const currentScrollPosition = textAreaScrollContainer.current.scrollTop

      tries++
      if (promptInputRef.current.scrollHeight === 0 && tries < 10) {
        // because this is (often) in a Portal, useLayoutEffect() can run before we're inserted in the DOM, and we are
        // thus unable to get a correct scrollHeight. in that case, let's try again in a bit
        // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
        setTimeout(adjustHeight, 1)
      }

      promptInputRef.current.style.height = '0'
      const scrollHeight = promptInputRef.current.scrollHeight
      const containerHeight = Math.min(Math.max(scrollHeight, MIN_HEIGHT), MAX_HEIGHT)

      // This 48px corresponds to --form-container-actions-height in CSS
      promptInputRef.current.style.height = `${containerHeight - 48}px`
      textAreaScrollContainer.current.style.height = `${containerHeight}px`
      textAreaScrollContainer.current.scrollTop = currentScrollPosition
    }

    adjustHeight()
  }, [promptText, promptInputRef])

  useEffect(() => {
    // Focus the image upload error banner when it appears
    if (imageUploadError) {
      imageUploadErrorRef.current?.focus()
    }
  }, [imageUploadError])

  const {data: workbenches} = useWorkbenchesQuery()

  const handlePromptKeydown = async (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key !== 'Enter' || e.shiftKey || isMobile()) return

    e.preventDefault()
    await handleSubmit()
  }

  const handlePromptChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const value = e.target.value
    setPromptText(value)

    setIsSubmittable(value.trim().length > 0)
  }

  const onSelect = useCallback(
    (e: React.MouseEvent | React.KeyboardEvent, tab: keyof typeof SparkTabs) => {
      e.preventDefault()
      if (selectedTab === tab) return
      setSelectedTab(tab)
    },
    [selectedTab],
  )

  const handleSubmit = async (message?: string) => {
    if (isSubmitting) return
    const submission = message ?? promptText
    if (submission.trim() === '') return

    workbenchStore.reloadQuota()

    setPromptText(submission)

    setIsSubmitting(true)
    const response = await verifiedFetchJSON('/copilot/spark', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: {},
    })
    if (response.ok) {
      const {id, billableOwner} = (await response.json()) as {id: string; billableOwner?: {login?: string}}
      const url = showUrl(id, billableOwner?.login)
      navigate(url)
    }
  }

  const removeImage = () => {
    clearImageAttachment()
    attachImageButtonRef.current?.focus()
  }

  return (
    <div className={styles.container} data-testid="dashboard-layout" data-hpc>
      <div className={styles.main}>
        <div className={styles.content}>
          <div className={clsx(styles.innerContent, 'my-md-10')}>
            <Stack direction="vertical" align="center" padding="normal">
              <SparkleFillIcon size={40} className={styles.icon} />
              <Heading as="h1" className={'text-center'}>
                <span className={styles.headerBlock}>Dream it.</span>{' '}
                <span className={styles.headerBlock}>See it.</span> <span className={styles.headerBlock}>Ship it.</span>
              </Heading>
              <p className={styles.description}>
                Transform ideas into full-stack intelligent apps in a snap. Publish with a click.
              </p>
              {copilotFeatureFlags.workbenchUserLimits &&
                banner !== BannerType.RUNTIME_LIMIT &&
                banner !== BannerType.COMPUTE_LIMIT && <SparkBanner />}
              {copilotFeatureFlags.workbenchUserLimits && <WorkbenchBanner />}
              <div ref={textAreaScrollContainer} className={styles.formContainer}>
                <Textarea
                  autoFocus
                  className={styles.promptInputContainer}
                  placeholder="Create intelligent prototypes, personal apps, websites and more"
                  ref={promptInputRef}
                  value={promptText}
                  onChange={handlePromptChange}
                  onKeyDown={handlePromptKeydown}
                  resize="none"
                />
                <div className={styles.formContainerActions}>
                  {promptImage ? (
                    <div role="toolbar" aria-label="Attachments" className={styles.attachmentToolbar}>
                      <div className={styles.referenceToken}>
                        <ImageIcon className="fgColor-muted" />
                        <span className={styles.referenceTokenLabel}>{promptImage.name}</span>
                        <IconButton
                          icon={XIcon}
                          variant="invisible"
                          size="small"
                          aria-label="Remove image"
                          onClick={removeImage}
                        />
                      </div>
                    </div>
                  ) : (
                    <>
                      <Button
                        variant="invisible"
                        leadingVisual={PaperclipIcon}
                        ref={attachImageButtonRef}
                        onClick={() => imagesInputRef.current?.click()}
                        className={styles.attachImageButton}
                      >
                        Attach image
                      </Button>
                      <input
                        id="image-uploader"
                        hidden
                        ref={imagesInputRef}
                        type="file"
                        accept={ACCEPTED_BASE64_IMAGE_FILE_MIME_TYPES.join(',')}
                        onChange={attachImage}
                      />
                    </>
                  )}
                  <IconButton
                    onClick={() => handleSubmit()}
                    icon={PaperAirplaneIcon}
                    aria-label="Submit prompt"
                    data-testid="submit-prompt"
                    tooltipDirection="n"
                    variant="invisible"
                    loading={isSubmitting}
                    loadingAnnouncement="Generating spark"
                    disabled={!isSubmittable}
                  />
                </div>
              </div>
              {imageUploadError && (
                <Banner
                  className={styles.alertBanner}
                  ref={imageUploadErrorRef}
                  variant="critical"
                  title="Error attaching image"
                  description={imageUploadError}
                  hideTitle
                  onDismiss={() => {
                    attachImageButtonRef.current?.focus()
                    setImageUploadError(undefined)
                  }}
                />
              )}
              <Stack
                direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}}
                wrap="wrap"
                gap={{narrow: 'normal', regular: 'condensed', wide: 'condensed'}}
                align={{narrow: 'stretch', regular: 'center', wide: 'center'}}
              >
                {suggestions &&
                  suggestions.map((suggestion: Icebreaker) => (
                    <SuggestionCard
                      key={suggestion.id}
                      titleHtml={suggestion.titleHtml as SafeHTMLString}
                      icon={suggestion.icon}
                      color={suggestion.color}
                      onClick={() => handleSubmit(suggestion.message)}
                    />
                  ))}
              </Stack>
              <LegalDisclaimer />
            </Stack>
            <UnderlineNav aria-label="Spark apps" className={styles.UnderlineNav}>
              <UnderlineNav.Item
                aria-current={selectedTab === 'Recent' ? 'page' : undefined}
                onSelect={e => onSelect(e, 'Recent')}
              >
                <div className={styles.underlinenavItem}>
                  <HistoryIcon /> Recents
                </div>
              </UnderlineNav.Item>
              <UnderlineNav.Item
                aria-current={selectedTab === 'Favorites' ? 'page' : undefined}
                onSelect={e => onSelect(e, 'Favorites')}
              >
                <div className={styles.underlinenavItem}>
                  <StarIcon /> Favorites
                </div>
              </UnderlineNav.Item>
            </UnderlineNav>
            {copilotFeatureFlags.workbenchUserLimits &&
              (banner === BannerType.RUNTIME_LIMIT || banner === BannerType.COMPUTE_LIMIT) && (
                <SparkBanner className="mt-4" />
              )}
            {selectedTab === 'Recent' && <SparksList items={workbenches} />}
            {selectedTab === 'Favorites' && <SparksList items={workbenches?.filter(w => w.favorite === true)} />}
          </div>
        </div>
      </div>
    </div>
  )
}

export default Layout
