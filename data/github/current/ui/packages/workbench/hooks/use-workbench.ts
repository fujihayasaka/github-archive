import type {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useCallback, useEffect, useRef, useState} from 'react'

import {useFilesContext} from '../contexts/FilesContext'
import type {FileDescription} from '../types/spark-history-types'
import type {Workbench} from '../types/workbench-types'
import {type FileStreamEvent, FileStreamEventType, generateIteration, type Step} from '../utilities/generate-iteration'
import {sparkFileUrl} from '../utilities/urls'

export interface UseWorkbenchProps {
  workbench: Workbench
  apiURL: string
  authTokenProvider: CopilotAuthTokenProvider
}

export interface UseWorkbenchReturn {
  previousRefinements: string[]
  isFetching: boolean
  currentFiles: Record<string, FileDescription>
  submitPrompt: (prompt: string, step: Step) => Promise<void>
}

const FILES_THAT_DISPLAY_WHEN_STREAMED: Record<string, boolean> = {
  'index.html': true,
  'src/App.tsx': true,
  'src/index.css': true,
}

export function useWorkbench({workbench, apiURL, authTokenProvider}: UseWorkbenchProps): UseWorkbenchReturn {
  const [previousRefinements, setPreviousRefinements] = useState<string[]>(workbench.previousRefinements || [])
  const [isFetching, setIsFetching] = useState(false)
  const [currentFiles, setCurrentFiles] = useState<Record<string, FileDescription>>({})
  const fileContentsRef = useRef<Record<string, string>>({})
  const {addFile, editFile} = useFilesContext()
  const initialPromptSubmitted = useRef(false)
  const navigate = useNavigate()

  const saveWorkbenchState = useCallback(
    async (files: Record<string, FileDescription>, refinements: string[]) => {
      const updatedWorkbench = {
        ...workbench,
        files,
        previousRefinements: refinements,
        shouldGenerateInitialPrompt: false,
      }

      await verifiedFetch(`/copilot/spark/workbench/${workbench.id}`, {
        method: 'POST',
        body: JSON.stringify(updatedWorkbench),
      })
    },
    [workbench],
  )

  const handleStreamEvent = useCallback(
    async (event: FileStreamEvent) => {
      switch (event.type) {
        case FileStreamEventType.NEW_FILE:
          addFile(event.fileName)
          fileContentsRef.current[event.fileName] = ''
          editFile({filePath: event.fileName, newFileContent: ''})

          if (FILES_THAT_DISPLAY_WHEN_STREAMED[event.fileName]) {
            navigate(sparkFileUrl({sparkId: workbench.id, path: event.fileName}))
          }
          break

        case FileStreamEventType.FILE_CONTENT_CHUNK: {
          const currentContent = fileContentsRef.current[event.fileName] || ''
          const newContent = currentContent + event.chunk
          fileContentsRef.current[event.fileName] = newContent
          editFile({filePath: event.fileName, newFileContent: newContent})
          break
        }

        case FileStreamEventType.COMPLETE: {
          const updatedFiles = event.files.reduce(
            (acc, file) => {
              acc[file.fileName] = file
              return acc
            },
            {} as Record<string, FileDescription>,
          )
          setCurrentFiles(updatedFiles)
          break
        }

        case FileStreamEventType.ERROR:
          setIsFetching(false)
          break
      }
    },
    [addFile, editFile],
  )

  const submitPrompt = useCallback(
    async (prompt: string, step: Step) => {
      if (!prompt.trim() || isFetching) return

      setIsFetching(true)
      fileContentsRef.current = {}

      try {
        const originalRefinements = previousRefinements
        const nextRefinements = [...previousRefinements, prompt]
        setPreviousRefinements(nextRefinements)

        // Then generate new content
        await generateIteration({
          prompt,
          generationType: step,
          editorState: {
            files: currentFiles,
            refinement_history: originalRefinements,
          },
          apiURL,
          authTokenProvider,
          onEvent: handleStreamEvent,
        })

        // Persist the new workbench state
        saveWorkbenchState(currentFiles, nextRefinements)
      } catch {
        setPreviousRefinements(previousRefinements)
      } finally {
        setIsFetching(false)
      }
    },
    [isFetching, previousRefinements, currentFiles, apiURL, authTokenProvider, handleStreamEvent, saveWorkbenchState],
  )

  // Handle initial prompt
  useEffect(() => {
    if (
      !initialPromptSubmitted.current &&
      !isFetching &&
      workbench.initialPrompt &&
      workbench.shouldGenerateInitialPrompt
    ) {
      initialPromptSubmitted.current = true
      submitPrompt(workbench.initialPrompt, 'generate')
    }
  }, [workbench.initialPrompt, isFetching, submitPrompt, workbench.shouldGenerateInitialPrompt])

  return {
    previousRefinements,
    isFetching,
    currentFiles,
    submitPrompt,
  }
}
