import {type Column, DataTable} from '@primer/react/experimental'
import {useId, useMemo} from 'react'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import type {CompareState} from '../prompt-compare-state'
import type {PromptConfig} from '../prompts'
import type {CompareRow, DatasetTableItem, EvalsRow, RowPromptResult} from '../types'
import {referencedVariablesInPrompt, VariableInput} from '../variables'
import {CompareTableBox} from './CompareTableBox'
import {InputCell} from './InputCell'
import {InputCellActions} from './InputCellActions'
import {OutputCell} from './OutputCell'

export function DatasetTable({
  prompts,
  columnMaxWidth,
  inputs,
  result,
  isRunning,
  compare,
  onAdd,
  onEdit,
}: {
  prompts: PromptConfig[]
  columnMaxWidth: string
  inputs: EvalsRow[]
  result?: {
    [rowId: number]: RowPromptResult[]
  }
  isRunning: boolean
  compare: CompareState
  onAdd: () => void
  onEdit: (input: EvalsRow) => void
}) {
  const allyId = useId()
  const dataRows = useMemo<DatasetTableItem[]>(() => {
    if (inputs.length === 0) {
      return [
        {
          id: 0,
          data: null,
        },
      ]
    }

    return inputs.map((input, index) => ({
      id: +input.id,
      data: input,
      result: result?.[index],
    }))
  }, [inputs, result])
  const {
    compare: {skippedRowIds},
  } = usePromptCompareState()

  // Get variables from the first prompt to generate input columns
  const promptVariables = useMemo(() => {
    if (prompts.length === 0 || !prompts[0]) return [VariableInput] // fallback to default
    const variables = referencedVariablesInPrompt(prompts[0])
    return variables.length > 0 ? variables : [VariableInput] // fallback if no variables found
  }, [prompts])

  const columns = [
    {
      id: 'input',
      header: 'Input',
      maxWidth: columnMaxWidth,
      renderCell(item: DatasetTableItem) {
        const skipped = skippedRowIds.has(item.id.toString())
        return (
          <InputCell row={item} skipped={skipped} variables={promptVariables}>
            <InputCellActions item={item} onAdd={onAdd} onEdit={onEdit} skipped={skipped} isRunning={isRunning} />
          </InputCell>
        )
      },
    },
    ...prompts.map((_prompt, index) => ({
      id: `prompt-${index}`,
      header: `Output ${index + 1}`,
      maxWidth: columnMaxWidth,
      renderCell: (row: CompareRow) => (
        <OutputCell
          skipped={skippedRowIds.has(row.id.toString())}
          firstUnskippedRowId={inputs.find(r => !skippedRowIds.has(r.id))?.id}
          row={row}
          index={index}
          dataRows={dataRows}
          isRunning={isRunning}
          compare={compare}
        />
      ),
    })),
  ] satisfies Array<Column<DatasetTableItem>>

  return (
    <CompareTableBox heading="Dataset" id={allyId}>
      <DataTable aria-labelledby={allyId} data={dataRows} columns={columns} />
    </CompareTableBox>
  )
}
