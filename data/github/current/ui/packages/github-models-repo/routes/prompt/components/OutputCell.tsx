import {clsx} from 'clsx'
import type {TokenUsage} from '@github-ui/github-models'
import {testIdProps} from '@github-ui/test-id-props'
import type {CompareState} from '../prompt-compare-state'
import type {EvaluatorState} from '../prompts'
import type {CompareRow, EvaluationResult, Message, RowPromptResult} from '../types'
import {CellResultPill} from './CellResultPill'
import {EvaluatorCell} from './EvaluatorCell'
import styles from './OutputCell.module.css'
import {TokenUsageWidget} from './TokenUsageWidget'

export function OutputCell({
  row,
  index,
  dataRows,
  isRunning,
  compare,
  skipped,
  firstUnskippedRowId,
}: {
  row: CompareRow
  index: number
  dataRows: CompareRow[]
  isRunning: boolean
  compare: CompareState
  skipped?: boolean
  firstUnskippedRowId?: string | undefined
}) {
  const rowResult: RowPromptResult | undefined = row.result?.[index]
  const prevRowResult: CompareRow | undefined = row.data?.id !== undefined ? dataRows[+row.data.id - 1] : undefined

  if (isRunning && !rowResult && !skipped) {
    return <LoadingState isFirstRow={row?.data?.id === firstUnskippedRowId} prevRowResult={prevRowResult} />
  }

  if (!rowResult) {
    return null
  }

  return (
    <div>
      <CellResults evalResults={rowResult.evals} evaluators={compare.evaluators} tokenUsage={rowResult?.tokenUsage} />
      <Completions completions={rowResult.completions} skipped={skipped} />
    </div>
  )
}

function LoadingState({
  isFirstRow,
  prevRowResult,
}: {
  isFirstRow?: boolean | undefined
  prevRowResult: CompareRow | undefined
}) {
  const hasPreviousResults = (prevRowResult?.result ?? []).length > 0

  const dots = (
    <span {...testIdProps('loading-dots')} className={styles.dots}>
      <span>.</span>
      <span>.</span>
      <span>.</span>
    </span>
  )

  return (
    <div className="d-flex flex-items-center flex-justify-center">
      {isFirstRow || hasPreviousResults ? <div className="color-fg-muted">Responding{dots}</div> : dots}
    </div>
  )
}

function CellResults({
  evalResults,
  evaluators,
  tokenUsage,
}: {
  evalResults: EvaluationResult[]
  evaluators: EvaluatorState[]
  tokenUsage?: TokenUsage
}) {
  return (
    <>
      {evaluators.map((e, eIdx) => {
        const eResult = evalResults?.[eIdx]
        if (!eResult) {
          return null
        }

        return (
          <CellResultPill key={`e-result-${e.config.name}`}>
            {e.config.name}: <EvaluatorCell r={eResult} />
          </CellResultPill>
        )
      })}
      <span className="color-fg-muted text-small mb-1">
        {tokenUsage && <TokenUsageWidget tokenUsage={tokenUsage} variant="pills" />}
      </span>
    </>
  )
}

function Completions({completions, skipped}: {completions: Message[]; skipped?: boolean}) {
  return (
    <div className={clsx({'fgColor-muted': skipped})}>
      {completions.map(c => (
        <div key={c.timestamp?.toString()}>{c.message}</div>
      ))}
    </div>
  )
}
