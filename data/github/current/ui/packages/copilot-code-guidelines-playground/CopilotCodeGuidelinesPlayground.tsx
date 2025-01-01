import styles from './CopilotCodeGuidelinesPlayground.module.css'

import Header from './components/Header'
import GuidelineForm from './components/GuidelineForm'
import Sample from './components/Sample'
import {PlaygroundContextProvider} from './PlaygroundContext'
import type {CodingGuideline, CodingGuidelinePath} from './PlaygroundContext'

export interface CopilotCodeGuidelinesPlaygroundProps {
  indexPath: string
  playgroundRunsPath: string
  saveCodeGuidelinePath: string
  sampleCodeGenerationsPath: string
  codingGuideline: CodingGuideline
  promptCharLimit: number
  codingGuidelinePaths: CodingGuidelinePath[]
}

export function CopilotCodeGuidelinesPlayground({
  indexPath,
  playgroundRunsPath,
  saveCodeGuidelinePath,
  sampleCodeGenerationsPath,
  codingGuideline,
  promptCharLimit,
  codingGuidelinePaths,
}: CopilotCodeGuidelinesPlaygroundProps) {
  return (
    <PlaygroundContextProvider
      initialCodingGuideline={codingGuideline}
      indexPath={indexPath}
      sampleCodeGenerationsPath={sampleCodeGenerationsPath}
      saveCodeGuidelinePath={saveCodeGuidelinePath}
      promptCharLimit={promptCharLimit}
      initialCodingGuidelinePaths={codingGuidelinePaths}
    >
      <CopilotCodeGuidelinesPlaygroundContent playgroundRunsPath={playgroundRunsPath} />
    </PlaygroundContextProvider>
  )
}

function CopilotCodeGuidelinesPlaygroundContent({playgroundRunsPath}: {playgroundRunsPath: string}) {
  return (
    <>
      <Header playgroundRunsPath={playgroundRunsPath} />
      <div className={`mt-3 d-flex flex-column flex-lg-row gap-3 ${styles.container}`}>
        <GuidelineForm />
        <Sample />
      </div>
    </>
  )
}
