import {useState} from 'react'
import {PipelineVisualizer} from './PipelineVisualizer'
import styles from './Pipeline.module.css'
import {usePipesStateLens} from '../contexts/PipesStateProvider'
import {currentPipeline} from '../state/lenses'

type ViewType = 'basic' | 'dashboard' | 'list' | 'compact'

interface PipelineProps {
  footerContent?: JSX.Element | null
}

export function CurrentPipeline({footerContent}: PipelineProps) {
  const hasCurrentPipeline = usePipesStateLens(s => !!currentPipeline(s))
  const [selectedView] = useState<ViewType>('compact')

  if (!hasCurrentPipeline) return null

  return (
    <>
      <div className={styles.container}>
        <PipelineVisualizer view={selectedView} />
      </div>
      <div className={styles.footer}>{footerContent}</div>
    </>
  )
}
