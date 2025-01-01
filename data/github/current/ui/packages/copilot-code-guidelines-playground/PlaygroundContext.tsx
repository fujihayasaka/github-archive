import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type React from 'react'
import {createContext, useContext, useMemo, useState} from 'react'

export type CodeComment = {
  lineNumber: number
  details: string
}

export const SampleCodeStatus = {
  WaitingToRun: 'WaitingToRun',
  Loading: 'Loading',
  Loaded: 'Loaded',
} as const

export type SampleCodeStatus = (typeof SampleCodeStatus)[keyof typeof SampleCodeStatus]

export type CodingGuideline = {
  id: number | null // null if we're creating a new guideline, otherwise the ID of the existing guideline
  name: string | null
  description: string | null
  exampleCodeViolations: string | null
}

export type CodingGuidelinePath = {
  id: number | null
  path: string | null
  markedForDestroy: boolean
}

interface PlaygroundContextType {
  sampleCode: string | null
  setSampleCode: React.Dispatch<React.SetStateAction<string | null>>
  promptCharLimit: number
  // When true, the server is generating code review comments
  sampleCodeStatus: SampleCodeStatus
  setSampleCodeStatus: React.Dispatch<React.SetStateAction<SampleCodeStatus>>
  // When true, the server is saving the coding guideline
  isSaving: boolean
  codeComments: CodeComment[]
  setCodeComments: React.Dispatch<React.SetStateAction<CodeComment[]>>
  // Used to populate the initial form values
  initialCodingGuideline: CodingGuideline
  // The current form values for the coding guideline
  currentCodingGuideline: CodingGuideline
  setCurrentCodingGuideline: React.Dispatch<React.SetStateAction<CodingGuideline>>
  errorMessage: string | null
  setErrorMessage: React.Dispatch<React.SetStateAction<string | null>>
  nameErrorMessage: string | null
  setNameErrorMessage: React.Dispatch<React.SetStateAction<string | null>>
  descriptionErrorMessage: string | null
  setDescriptionErrorMessage: React.Dispatch<React.SetStateAction<string | null>>
  indexPath: string
  saveCodeGuidelinePath: string
  sampleCodeGenerationsPath: string
  saveCodeGuideline: () => Promise<void>
  codingGuidelinePaths: CodingGuidelinePath[]
  setCodingGuidelinePaths: React.Dispatch<React.SetStateAction<CodingGuidelinePath[]>>
  showTabBar: boolean
  occurrencesPath: string
}

const PlaygroundContext = createContext<PlaygroundContextType | undefined>(undefined)

export const PlaygroundContextProvider: React.FC<
  React.PropsWithChildren<{
    initialCodingGuideline: CodingGuideline
    indexPath: string
    saveCodeGuidelinePath: string
    sampleCodeGenerationsPath: string
    promptCharLimit: number
    initialCodingGuidelinePaths: CodingGuidelinePath[]
    showTabBar: boolean
    occurrencesPath: string
  }>
> = ({
  children,
  initialCodingGuideline,
  indexPath,
  saveCodeGuidelinePath,
  sampleCodeGenerationsPath,
  promptCharLimit,
  initialCodingGuidelinePaths,
  showTabBar,
  occurrencesPath,
}) => {
  const [sampleCode, setSampleCode] = useState<string | null>(null)
  const [sampleCodeStatus, setSampleCodeStatus] = useState<SampleCodeStatus>(SampleCodeStatus.WaitingToRun)
  const [isSaving, setIsSaving] = useState(false)
  const [codeComments, setCodeComments] = useState([] as Array<{lineNumber: number; details: string}>)
  const [currentCodingGuideline, setCurrentCodingGuideline] = useState<CodingGuideline>(initialCodingGuideline)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [nameErrorMessage, setNameErrorMessage] = useState<string | null>(null)
  const [descriptionErrorMessage, setDescriptionErrorMessage] = useState<string | null>(null)
  const [codingGuidelinePaths, setCodingGuidelinePaths] = useState<CodingGuidelinePath[]>(initialCodingGuidelinePaths)

  const value = useMemo(() => {
    async function saveCodeGuideline(event?: Event) {
      event?.preventDefault()
      if (isSaving) return
      setIsSaving(true)
      const {name, description, exampleCodeViolations} = currentCodingGuideline
      const method = initialCodingGuideline.id ? 'PUT' : 'POST'
      const resp = await verifiedFetchJSON(saveCodeGuidelinePath, {
        body: {
          copilot_coding_guideline: {
            name,
            description,
            example_code_violations: exampleCodeViolations,
            paths_attributes: codingGuidelinePaths.map(path => {
              return {
                id: path.id,
                path: path.path,
                _destroy: path.markedForDestroy,
              }
            }),
          },
        },
        method,
      })

      if (resp.ok) {
        // The CopilotCodeGuidelinesController will show a flash message if the flash param is present and matches
        // an action defined in the controller such as 'updated' or 'created'
        const flash = initialCodingGuideline.id ? 'updated' : 'created'

        // eslint-disable-next-line react-hooks/react-compiler
        window.location.href = `${indexPath}?flash=${flash}`
      } else {
        const errorResponse = await resp.json()
        // if there are no field-specific errors show the full message
        if (!Object.keys(errorResponse.errors ?? {}).length) {
          setErrorMessage(errorResponse.errorMessage)
        } else {
          // if there are field-specific errors check the fields we're expecting
          if (errorResponse.errors?.name?.length) {
            setNameErrorMessage(errorResponse.errors.name[0])
            delete errorResponse.errors.name
          }
          if (errorResponse.errors?.description?.length) {
            setDescriptionErrorMessage(errorResponse.errors.description[0])
            delete errorResponse.errors.description
          }

          // if there are unexpected field errors show the full message
          if (Object.keys(errorResponse.errors).length) setErrorMessage(errorResponse.errorMessage)
        }

        // Only set isSaving(false) when it fails since we want to show an error message. On success we redirect so
        // we want to keep the loading state going until the page starts to transition
        setIsSaving(false)
      }
    }

    return {
      promptCharLimit,
      sampleCode,
      setSampleCode,
      sampleCodeStatus,
      setSampleCodeStatus,
      isSaving,
      codeComments,
      setCodeComments,
      initialCodingGuideline,
      currentCodingGuideline,
      setCurrentCodingGuideline,
      errorMessage,
      setErrorMessage,
      nameErrorMessage,
      setNameErrorMessage,
      descriptionErrorMessage,
      setDescriptionErrorMessage,
      saveCodeGuideline,
      indexPath,
      saveCodeGuidelinePath,
      sampleCodeGenerationsPath,
      codingGuidelinePaths,
      setCodingGuidelinePaths,
      showTabBar,
      occurrencesPath,
    }
  }, [
    promptCharLimit,
    sampleCode,
    sampleCodeStatus,
    isSaving,
    codeComments,
    initialCodingGuideline,
    currentCodingGuideline,
    errorMessage,
    nameErrorMessage,
    descriptionErrorMessage,
    indexPath,
    saveCodeGuidelinePath,
    sampleCodeGenerationsPath,
    codingGuidelinePaths,
    showTabBar,
    occurrencesPath,
  ])

  return <PlaygroundContext.Provider value={value}>{children}</PlaygroundContext.Provider>
}

export const usePlaygroundContext = () => {
  const context = useContext(PlaygroundContext)
  if (context === undefined) {
    throw new Error('usePlaygroundContext must be used within a PlaygroundContextProvider')
  }
  return context
}
