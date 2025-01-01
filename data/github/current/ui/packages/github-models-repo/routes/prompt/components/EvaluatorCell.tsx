import {Label} from '@primer/react'
import type {EvaluationResult} from '../evals-sdk/evaluator/evaluator'

export function EvaluatorCell({r}: {r: EvaluationResult}) {
  if (!r) {
    return null
  }

  if (r.error) {
    return <span>{r.error}</span>
  }

  // Always map scores to pass/fail for now
  if (r.pass !== undefined) {
    return r.pass ? <Label variant="success">Pass</Label> : <Label variant="danger">Fail</Label>
  }

  if (r.score !== undefined) {
    const scoreColor = getScoreColor(r.score)
    return (
      <Label
        size="small"
        style={{
          color: scoreColor.color,
          borderColor: scoreColor.borderColor,
        }}
      >
        {r.score * 100.0}%
      </Label>
    )
  }

  return null
}

function getScoreColor(score: number): {color: string; borderColor: string} {
  switch (true) {
    case score <= 0:
      return {
        color: 'var(--data-red-color-emphasis)',
        borderColor: 'var(--data-red-color-emphasis)',
      }
    case score > 0 && score < 0.25:
      return {
        color: 'var(--data-orange-color-emphasis)',
        borderColor: 'var(--data-orange-color-emphasis)',
      }
    case score >= 0.25 && score < 0.5:
      return {
        color: 'var(--data-yellow-color-emphasis)',
        borderColor: 'var(--data-yellow-color-emphasis)',
      }
    case score >= 0.5 && score < 0.75:
      return {
        color: 'var(--data-teal-color-emphasis)',
        borderColor: 'var(--data-teal-color-emphasis)',
      }
    case score >= 0.75:
      return {
        color: 'var(--data-green-color-emphasis)',
        borderColor: 'var(--data-green-color-emphasis)',
      }
  }

  return {
    color: 'var(--data-gray-color-emphasis)',
    borderColor: 'var(--data-gray-color-emphasis)',
  }
}
