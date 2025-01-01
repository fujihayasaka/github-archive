import {DataTable, type Column} from '@primer/react/experimental'
import {useCallback, useId, useMemo, type ReactNode} from 'react'
import type {RepoModel} from '../../../types'
import {usePromptCompareManager} from '../prompt-compare-manager'
import type {PromptConfig} from '../prompts'
import {ComparePromptActions} from './ComparePromptActions'
import {CompareTableBox} from './CompareTableBox'
import {InlinePrompt} from './InlinePrompt'
import styles from './PromptsTable.module.css'
import type {CompareMode} from '../types'

export function PromptsTable({
  columnMaxWidth,
  onModelSelect,
  onPromptEdit,
  mode,
  prompts,
  renderEvaluatorsConfig,
}: {
  prompts: PromptConfig[]
  mode: CompareMode
  columnMaxWidth: string
  onPromptEdit: (prompt: PromptConfig, index: number) => void
  onModelSelect: (model: RepoModel, promptIndex: number) => void
  renderEvaluatorsConfig?: ReactNode
}) {
  const manager = usePromptCompareManager()
  const onPromptRemove = useCallback((idx: number) => manager.removePrompt(idx), [manager])
  const allyId = useId()

  type DataItem = {id: string; data: PromptConfig[]}

  const promptsData = useMemo<DataItem[]>(
    () => [
      {
        id: 'prompts',
        data: prompts,
      },
    ],
    [prompts],
  )

  const columns = [
    {
      id: 'input',
      header() {
        return 'Evaluators'
      },
      maxWidth: columnMaxWidth,
      renderCell() {
        return (
          renderEvaluatorsConfig || (
            <span className="color-fg-muted">
              Evaluators rank your prompts against specific criteria you can configure.
            </span>
          )
        )
      },
    },
    ...prompts.map((_, index) => ({
      id: `prompt-${index}`,
      header: `Prompt ${index + 1}`,
      maxWidth: columnMaxWidth,
      renderCell(row: DataItem) {
        const prompt = row.data[index]!
        const canEdit = mode !== 'review' || index > 0

        return (
          <InlinePrompt prompt={prompt} promptIndex={index} onModelSelect={canEdit ? onModelSelect : undefined}>
            <ComparePromptActions
              promptIndex={index}
              prompt={prompt}
              handleEdit={onPromptEdit}
              handleRemove={onPromptRemove}
              reviewView={mode === 'review'}
              canEdit={canEdit}
            />
          </InlinePrompt>
        )
      },
    })),
  ] satisfies Array<Column<DataItem>>

  return (
    <CompareTableBox heading="Prompts" id={allyId} className={styles.PromptsTable}>
      <DataTable aria-labelledby={allyId} data={promptsData} columns={columns} />
    </CompareTableBox>
  )
}
