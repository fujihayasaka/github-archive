import type {
  HydratedIssueReference,
  PullRequest,
  DiffData,
  NavigationUrls,
  FileCategory,
  ExplanationDepth,
} from '../utils/types'

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {useEffect, useState, useRef, useMemo} from 'react'
import {generateMarkdownWalkthrough} from '../utils/generate-markdown-walkthrough'
import {DEFAULT_SETTINGS, DEFAULT_TEMPLATE} from '../utils/settings'
import {parseDiffsToHunks} from '../utils/parse-diffs-to-hunks'
import HypersightLayout from '../components/HypersightLayout'
import {HeadingProvider} from '../utils/HeadingContext'

export interface HypersightPayload {
  pullRequest: PullRequest
  mentionedIssues: HydratedIssueReference[]
  apiUrl: string
  diffs: Record<FileCategory, DiffData[]>
  urls: NavigationUrls
}

// Categories that should be processed by the LLM
const WALKTHROUGH_FILE_CATEGORIES: FileCategory[] = ['CODE', 'TESTS', 'DOCUMENTATION']

// Storage key for the explanation depth preference
const EXPLANATION_DEPTH_STORAGE_KEY = 'hypersightExplanationDepth'
const PREFERENCES_STORAGE_KEY = 'hypersightPreferences'

export function Hypersight() {
  const {apiUrl, diffs, mentionedIssues, pullRequest, urls} = useRoutePayload<HypersightPayload>()
  const [markdownContent, setMarkdownContent] = useState('')
  const [isWalkthroughComplete, setIsWalkthroughComplete] = useState(false)
  const [depth, setDepth] = useLocalStorage<ExplanationDepth>(EXPLANATION_DEPTH_STORAGE_KEY, 'Balanced')
  const [preferences, setPreferences] = useLocalStorage<string>(PREFERENCES_STORAGE_KEY, '')
  const effectRan = useRef(false)
  const userSettings = DEFAULT_SETTINGS
  const template = userSettings.templates[0] || DEFAULT_TEMPLATE

  const resetWalkthrough = () => {
    setMarkdownContent('')
    effectRan.current = false
  }

  // Filter diffs to only include categories we want to process with the LLM
  const walkthroughDiffs = useMemo(() => {
    return WALKTHROUGH_FILE_CATEGORIES.flatMap(category => diffs[category] || [])
  }, [diffs])

  // Collect non-walkthrough diffs for OtherChanges component
  const diffsNotInWalkthrough = useMemo(() => {
    const result = {...diffs}
    // Remove the walkthrough categories
    for (const category of WALKTHROUGH_FILE_CATEGORIES) {
      delete result[category]
    }
    return result as Record<FileCategory, DiffData[]>
  }, [diffs])

  const walkthroughDiffHunks = useMemo(() => {
    return parseDiffsToHunks(walkthroughDiffs)
  }, [walkthroughDiffs])

  useEffect(() => {
    if (effectRan.current) return
    effectRan.current = true

    // Reset walkthrough completion state when starting a new generation
    setIsWalkthroughComplete(false)

    const generateWalkthrough = async () => {
      await generateMarkdownWalkthrough({
        apiUrl,
        pullRequest,
        diffHunks: walkthroughDiffHunks,
        mentionedIssues,
        streamCallback: (chunk: string) => {
          setMarkdownContent(prev => prev + chunk)
        },
        template,
        depth,
        preferences,
      })
      // Mark walkthrough as complete when generation is finished
      setIsWalkthroughComplete(true)
    }

    generateWalkthrough()
  }, [walkthroughDiffHunks, template, apiUrl, pullRequest, mentionedIssues, depth, preferences])

  const handleDepthChange = (newDepth: ExplanationDepth) => {
    resetWalkthrough()
    setDepth(newDepth)
  }

  const handlePreferencesChange = (newPreferences: string) => {
    resetWalkthrough()
    setPreferences(newPreferences)
  }

  return (
    <HeadingProvider>
      <HypersightLayout
        pullRequest={pullRequest}
        urls={urls}
        markdownContent={markdownContent}
        isWalkthroughComplete={isWalkthroughComplete}
        walkthroughDiffHunks={walkthroughDiffHunks}
        nonProcessedDiffs={diffsNotInWalkthrough}
        apiUrl={apiUrl}
        extractedIssues={mentionedIssues}
        depth={depth}
        onDepthChange={handleDepthChange}
        preferences={preferences}
        onPreferencesChange={handlePreferencesChange}
      />
    </HeadingProvider>
  )
}
