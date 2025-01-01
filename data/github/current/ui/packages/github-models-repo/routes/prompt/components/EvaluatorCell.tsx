import type {EvaluationResult} from '../types'
import styles from './EvaluatorCell.module.css'

export function EvaluatorCell({r}: {r: EvaluationResult}) {
  if (!r) {
    return null
  }

  if (r.error) {
    return <span>{r.error}</span>
  }

  // Always map scores to pass/fail for now
  if (r.pass !== undefined) {
    return r.pass ? <span className={styles.success}>Pass</span> : <span className={styles.error}>Fail</span>
  }

  if (r.score !== undefined) {
    const scoreColor = getScoreColor(r.score)
    return (
      <span
        style={{
          color: scoreColor.color,
          fontWeight: 'bold',
        }}
      >
        {r.score * 100.0}%
      </span>
    )
  }

  return null
}

function getScoreColor(score: number): {color: string} {
  switch (true) {
    case score <= 0:
      return {
        color: 'var(--data-red-color-emphasis)',
      }
    case score > 0 && score < 0.25:
      return {
        color: 'var(--data-orange-color-emphasis)',
      }
    case score >= 0.25 && score < 0.5:
      return {
        color: 'var(--data-yellow-color-emphasis)',
      }
    case score >= 0.5 && score < 0.75:
      return {
        color: 'var(--data-teal-color-emphasis)',
      }
    case score >= 0.75:
      return {
        color: 'var(--data-green-color-emphasis)',
      }
  }

  return {
    color: 'var(--data-gray-color-emphasis)',
  }
}
