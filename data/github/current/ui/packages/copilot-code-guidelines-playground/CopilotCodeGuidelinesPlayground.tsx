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
  showTabBar: boolean
  occurrencesPath: string
}

export function CopilotCodeGuidelinesPlayground({
  indexPath,
  playgroundRunsPath,
  saveCodeGuidelinePath,
  sampleCodeGenerationsPath,
  codingGuideline,
  promptCharLimit,
  codingGuidelinePaths,
  showTabBar,
  occurrencesPath,
}: CopilotCodeGuidelinesPlaygroundProps) {
  return (
    <PlaygroundContextProvider
      initialCodingGuideline={codingGuideline}
      indexPath={indexPath}
      sampleCodeGenerationsPath={sampleCodeGenerationsPath}
      saveCodeGuidelinePath={saveCodeGuidelinePath}
      promptCharLimit={promptCharLimit}
      initialCodingGuidelinePaths={codingGuidelinePaths}
      showTabBar={showTabBar}
      occurrencesPath={occurrencesPath}
    >
      <CopilotCodeGuidelinesPlaygroundContent playgroundRunsPath={playgroundRunsPath} />
    </PlaygroundContextProvider>
  )
}

function CopilotCodeGuidelinesPlaygroundContent({playgroundRunsPath}: {playgroundRunsPath: string}) {
  return (
    <>
      <Header />
      <div className={`mt-3 d-flex flex-column flex-lg-row gap-3 ${styles.container}`}>
        <GuidelineForm />
        <Sample playgroundRunsPath={playgroundRunsPath} />
      </div>
    </>
  )
}
