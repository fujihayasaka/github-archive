import {Button, Stack} from '@primer/react'
import {maxRowsLimit} from '../constants'
import {PlusIcon, UploadIcon} from '@primer/octicons-react'

interface AddCompareRowsControlsProps {
  onAddRow: () => void
  onImportRows: () => void
  totalRows: number
}

export function AddCompareRowsControls({onAddRow, onImportRows, totalRows}: AddCompareRowsControlsProps) {
  const canAddRow = totalRows < maxRowsLimit

  return (
    <Stack direction="horizontal" justify="end" gap="condensed">
      <Button size="small" leadingVisual={PlusIcon} onClick={onAddRow} disabled={!canAddRow}>
        Add input
      </Button>
      <Button size="small" leadingVisual={UploadIcon} onClick={onImportRows} disabled={!canAddRow}>
        Import data
      </Button>
    </Stack>
  )
}
