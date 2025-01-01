import type {OnDropArgs} from '@github-ui/drag-and-drop'
import {DragAndDrop, MoveDialogTrigger} from '@github-ui/drag-and-drop'
import {ArrowSwitchIcon} from '@primer/octicons-react'
import {Button, IconButton} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useState} from 'react'

interface FunnelOrderingDialogProps {
  initialOrder: string[]
  onSubmit: (newOrder: string[]) => void
  closeDialog: () => void
}

export function FunnelOrderingDialog({initialOrder, onSubmit, closeDialog}: FunnelOrderingDialogProps): JSX.Element {
  const [items, setItems] = useState(initialOrder.map(category => ({id: category, title: category})))

  const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>): void => {
    if (dragMetadata.id === dropMetadata?.id) return
    const dragItem = items.find(item => item.id === dragMetadata.id)
    if (!dragItem) return
    const newItems = items.filter(item => item.id !== dragItem.id)
    const dropIndex = newItems.findIndex(item => item.id === dropMetadata?.id)
    if (dropIndex === -1) return

    if (isBefore) {
      newItems.splice(dropIndex, 0, dragItem)
    } else {
      newItems.splice(dropIndex + 1, 0, dragItem)
    }
    setItems(newItems)
  }

  const handleApply = (): void => {
    onSubmit(items.map(item => item.id))
    closeDialog()
  }

  // Extracted row rendering to apply consistent layout & alignment
  const renderRow = (item: {id: string; title: string}, index: number) => (
    <DragAndDrop.Item
      index={index}
      id={item.id}
      key={item.id}
      title={item.title}
      containerStyle={{display: 'flex'}}
      style={{
        display: 'grid',
        alignItems: 'center',
        gridTemplateColumns: 'min-content 1fr min-content',
        width: '100%',
      }}
    >
      <div style={{display: 'flex', alignItems: 'center', gap: '8px', overflow: 'hidden', minWidth: 0}}>
        <div
          style={{
            width: '20px',
            height: '20px',
            borderRadius: '50%',
            backgroundColor: 'gray',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          {index + 1}
        </div>
        <span style={{whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'}}>{item.title}</span>
      </div>
      <MoveDialogTrigger
        Component={IconButton}
        icon={ArrowSwitchIcon}
        variant="invisible"
        style={{transform: 'rotate(90deg)'}}
        aria-label={`Advanced move ${item.title}`}
      />
    </DragAndDrop.Item>
  )

  return (
    <Dialog
      onClose={closeDialog}
      title="Configure funnel order"
      aria-labelledby="funnel-order-dialog-title"
      width="large"
    >
      <Dialog.Body>
        <DragAndDrop
          items={items}
          onDrop={onDrop}
          aria-label="Reorder Categories"
          renderOverlay={(item, index) => renderRow(item, index)}
        >
          {items.map((item, index) => renderRow(item, index))}
        </DragAndDrop>
      </Dialog.Body>
      <Dialog.Footer>
        <Button variant="primary" onClick={handleApply}>
          Move
        </Button>
      </Dialog.Footer>
    </Dialog>
  )
}
