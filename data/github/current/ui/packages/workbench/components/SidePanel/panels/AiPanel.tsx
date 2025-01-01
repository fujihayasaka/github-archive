import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {keepPreviousData, useQuery} from '@github-ui/react-query'
import {AiModelIcon} from '@primer/octicons-react'
import {ActionList, Dialog, Textarea} from '@primer/react'
import {useCallback, useEffect, useRef, useState} from 'react'

import {useFilesContext} from '../../../contexts/FilesContext'
import {useFileSyncerContext} from '../../../contexts/FileSyncerContext'
import {useFetchFromCodespaceApi} from '../../../hooks/use-fetch-from-codespace-api'
import {Region, RegionState, useRegionState} from '../../../hooks/use-region-state'
import {PanelBlankslate} from '../PanelBlankslate'
import {Section} from '../Section'
import styles from './AiPanel.module.css'

export interface AiPanelProps {
  isFetching: boolean
  workbenchId: string
}

type Prompt = {
  file: string
  description: string
  uniqueFileId: string
}

type File = {
  file: string
  originalContents: string
}

const FILE_EXTENSIONS = ['.js', '.ts', '.jsx', '.tsx']

export function AiPanel({isFetching, workbenchId}: AiPanelProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const [oldPrompts, setPrompts] = useState<Prompt[]>([])
  const [files, setFiles] = useState<File[]>([])
  const [isFetchingFiles, setIsFetchingFiles] = useState(true)
  const [isProcessingFiles, setIsProcessingFiles] = useState(true)
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [selectedPrompt, setSelectedPrompt] = useState<Prompt | null>(null)
  const [promptContent, setPromptContent] = useState('')
  const richAiPromptParsingEnabled = useFeatureFlag('copilot_workbench_rich_ai_prompt_parsing')
  const cachedAiPanelEnabled = isFeatureEnabled('copilot_workbench_cached_ai_panel') && richAiPromptParsingEnabled
  const {fetchFromCodespaceApi} = useFetchFromCodespaceApi()
  const {getFileSyncerV2, forceContentRefresh, lastEditStateStamp} = useFileSyncerContext()

  const {getFileList, editFile} = useFilesContext()
  const readOnly = useRegionState(Region.AI) === RegionState.READ_ONLY

  const resetDialogState = useCallback(() => {
    setIsDialogOpen(false)
    setSelectedPrompt(null)
    setPromptContent('')
  }, [])

  useEffect(() => {
    if (richAiPromptParsingEnabled) {
      setIsFetchingFiles(false)
      setIsProcessingFiles(false)
      return
    }
    // Gets files that should be scraped for prompts
    const fetchFilesAndPrompts = async () => {
      const fileSyncer = getFileSyncerV2()
      if (!fileSyncer) {
        setIsFetchingFiles(false)
        return
      }

      setIsFetchingFiles(true)
      const fetchedFiles = getFileList()
      // Filter out directories and files that don't match the extensions
      const filteredFiles = fetchedFiles.filter(
        file => file.type === 'file' && FILE_EXTENSIONS.some(fileExtension => file.path.endsWith(fileExtension)),
      )
      // Get original content for each file
      const fileContents = await Promise.all(
        filteredFiles.map(async file => {
          const content = await fileSyncer.readFileString(file.path)
          return {file: file.path, originalContents: content}
        }),
      )

      setIsFetchingFiles(false)
      setFiles(fileContents)
    }
    fetchFilesAndPrompts()
  }, [workbenchId, lastEditStateStamp, getFileSyncerV2, getFileList, richAiPromptParsingEnabled])

  const fetchPrompts = useCallback(async () => {
    setIsFetchingFiles(false)
    if (oldPrompts.length === 0) {
      // Only set the loading state if we are fetching prompts for the first time
      // to avoid having it flashing in and out as the user types.
      setIsProcessingFiles(true)
    }
    try {
      const res = await fetchFromCodespaceApi('/prompts')

      if (!res.ok) {
        setIsProcessingFiles(false)
        throw new Error(`Failed to fetch prompts: ${res.statusText}`)
      }

      const json: {data: {prompts: Prompt[]}} = await res.json()
      setIsProcessingFiles(false)
      setPrompts(json.data.prompts)
      return json.data.prompts
    } finally {
      setIsProcessingFiles(false)
    }
  }, [fetchFromCodespaceApi, oldPrompts.length])

  const {data: cachedPrompts, isLoading} = useQuery<Prompt[]>({
    enabled: cachedAiPanelEnabled,
    queryKey: ['fetchPrompts', lastEditStateStamp],
    queryFn: async () => await fetchPrompts(),
    placeholderData: keepPreviousData,
    staleTime: Infinity,
    refetchOnWindowFocus: false,
    refetchOnMount: false,
    refetchOnReconnect: false,
    refetchInterval: false,
  })

  const prompts = cachedAiPanelEnabled ? cachedPrompts ?? [] : oldPrompts
  const loading = cachedAiPanelEnabled ? isLoading : isFetchingFiles || isProcessingFiles

  const processFiles = useCallback(async () => {
    const newPrompts: Prompt[] = []
    const fileSyncer = getFileSyncerV2()
    if (!fileSyncer) {
      setIsFetchingFiles(false)
      return
    }

    setIsProcessingFiles(true)

    // Gets content of each file and checks for / extracts prompts
    for (const {file} of files) {
      const fileContent = await fileSyncer.readFileString(file)

      if (fileContent) {
        let currentIndex = 0
        let promptCount = 0

        while (true) {
          const startIndex = fileContent.indexOf('spark.llmPrompt`', currentIndex)
          if (startIndex === -1) break

          const promptStartIndex = startIndex + 'spark.llmPrompt`'.length
          const endIndex = fileContent.indexOf('`', promptStartIndex)

          if (endIndex !== -1) {
            const prompt = fileContent.substring(promptStartIndex, endIndex)
            newPrompts.push({
              file,
              description: prompt,
              uniqueFileId: `${file}${promptCount > 0 ? ` (${promptCount + 1})` : ''}`,
            })
            promptCount++
            currentIndex = endIndex + 1
          }
        }
      }
    }

    setIsProcessingFiles(false)
    setPrompts(newPrompts)
  }, [files, getFileSyncerV2])

  useEffect(() => {
    if (cachedAiPanelEnabled) {
      return
    }
    if (richAiPromptParsingEnabled) {
      fetchPrompts()
    } else {
      processFiles()
    }
  }, [processFiles, lastEditStateStamp, richAiPromptParsingEnabled, fetchPrompts, cachedAiPanelEnabled])

  const handleUpdate = async (file: string, previousPrompt: string, newPrompt: string) => {
    setIsDialogOpen(false)
    setSelectedPrompt(null)
    setPromptContent('')

    // Get original content from state based on the file
    const originalContent = files.find(f => f.file === file)?.originalContents

    // Get current file content, but replace only the prompt with the new content
    const fileSyncer = getFileSyncerV2()
    if (!fileSyncer) {
      return
    }
    const fileContent = await fileSyncer.readFileString(file)

    if (fileContent) {
      // Find the current instance of the prompt that is being edited (previousPrompt)
      const startIndex = fileContent.indexOf(previousPrompt)
      const endIndex = startIndex + previousPrompt.length
      // Replace the prompt with the new content
      const newContent = fileContent.substring(0, startIndex) + newPrompt + fileContent.substring(endIndex)

      await editFile({filePath: file, originalContent, newFileContent: newContent})
      forceContentRefresh()
      if (!richAiPromptParsingEnabled) {
        processFiles()
      }
    }
  }

  const handlePromptClick = (prompt: Prompt) => {
    setSelectedPrompt(prompt)
    setPromptContent(prompt.description)
    setIsDialogOpen(true)
  }

  const handleDescriptionChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setPromptContent(e.target.value)
  }

  if (!loading && (isFetching || prompts.length === 0)) {
    return (
      <div className="mt-3">
        <PanelBlankslate
          icon={AiModelIcon}
          title="No AI features added yet"
          description="Use the Iterate tab to add AI features to your spark."
        />
      </div>
    )
  }

  return (
    <div className="mt-3">
      <Section title="Prompts" showTitle={false} readOnly={readOnly} loading={loading}>
        <Section.Items>
          <ActionList className={styles.actionList}>
            {prompts.map(prompt => {
              const id = prompt.uniqueFileId.replace(/[^a-zA-Z0-9]/g, '-').replace(/-+/g, '-')
              return (
                <ActionList.Item
                  className={styles.listItem}
                  key={id}
                  id={`edit-${id}`}
                  onSelect={() => handlePromptClick(prompt)}
                >
                  <ActionList.LeadingVisual>
                    <AiModelIcon />
                  </ActionList.LeadingVisual>
                  {prompt.uniqueFileId}
                  <ActionList.Description variant="block">{prompt.description}</ActionList.Description>
                </ActionList.Item>
              )
            })}
          </ActionList>
        </Section.Items>
        {isDialogOpen && selectedPrompt && (
          <Dialog
            title="Edit prompt"
            footerButtons={[
              {
                buttonType: 'default',
                content: 'Cancel',
                onClick: resetDialogState,
              },
              {
                buttonType: 'primary',
                content: 'Update',
                onClick: async () => await handleUpdate(selectedPrompt.file, selectedPrompt.description, promptContent),
              },
            ]}
            onClose={resetDialogState}
          >
            <Textarea block ref={textareaRef} value={promptContent} onChange={handleDescriptionChange} rows={15} />
          </Dialog>
        )}
      </Section>
    </div>
  )
}
