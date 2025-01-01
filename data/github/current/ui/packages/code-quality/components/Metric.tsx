import DataCard from '@github-ui/data-card'
import {Grade, gradeToText} from '../types/grade'
import {ProgressBar} from '@primer/react'
import styles from './Metric.module.css'

export interface MetricProps {
  title: string
  data?: {
    grade: Grade
    findingsCount: number
  }
}

export function Metric({title, data}: MetricProps) {
  const findingsCount = data?.findingsCount || 0

  return (
    <DataCard cardTitle={title}>
      <p className="color-fg-subtle f4 font-light lh-condensed">{data ? gradeToText[data.grade] : 'No data'}</p>
      <MetricProgressBar grade={data ? data.grade : undefined} />
      <DataCard.Description>{findingsCount} findings</DataCard.Description>
    </DataCard>
  )
}

function MetricProgressBar({grade}: {grade?: Grade}) {
  const getColors = (g?: Grade) => {
    switch (g) {
      case Grade.A:
        return {activeColor: 'success.emphasis', activeCount: 4}
      case Grade.B:
        return {activeColor: 'success.emphasis', activeCount: 3}
      case Grade.C:
        return {activeColor: 'attention.emphasis', activeCount: 2}
      case Grade.D:
        return {activeColor: 'danger.emphasis', activeCount: 1}
      default:
        return {activeColor: 'muted.emphasis', activeCount: 0}
    }
  }

  const {activeColor, activeCount} = getColors(grade)
  const totalSegments = 4
  const progressPerSegment = 100 / totalSegments

  return (
    <ProgressBar barSize="small" className={styles.ProgressBar} aria-label={`Code quality grade: ${grade}`}>
      {Array.from({length: totalSegments}, (_, i) => (
        <ProgressBar.Item
          key={i}
          bg={i < activeCount ? activeColor : 'neutral.emphasis'}
          progress={progressPerSegment}
          aria-label={i < activeCount ? 'Progress segment' : 'Inactive segment'}
          aria-valuenow={progressPerSegment}
        />
      ))}
    </ProgressBar>
  )
}
