import {DragAndDrop, DragAndDropContext} from '@github-ui/drag-and-drop'
import {noop} from '@github-ui/noop'
import {createContext, useContext, useMemo} from 'react'

import type {NormalizedPageView} from '../../hooks/use-view-state-reducer/types'
import {useViews} from '../../hooks/use-views'

export type MoveTabDialogProps = {
  selectedTab: Pick<NormalizedPageView, 'number' | 'id' | 'name'>
  returnRef: React.RefObject<HTMLButtonElement>
}

export const MoveTabDialog = ({close, selectedTab, returnRef}: MoveTabDialogProps & {close: () => void}) => {
  const {views, updateViewPriority} = useViews()

  return (
    <DragAndDropContext.Provider
      value={useMemo(
        () => ({
          dragIndex: null, // This is not used by the MoveDialog, so it can be null
          overId: null, // This is not used by the MoveDialog, so it can be null
          direction: 'vertical', // This is not used by the MoveDialog, so it can be `vertical`
          isInDragMode: false, // This is not used by the MoveDialog, so it can be false
          moveDialogItem: {
            title: selectedTab.name,
            index: views.findIndex(view => view.id === selectedTab.id),
          },
          openMoveDialog: noop, // This is not used by the MoveDialog, so it can be a noop
          moveToPosition: (async (currentPosition: number, newPosition: number, isBefore?: boolean) => {
            const activeItem = views[currentPosition]
            const overItem = views[newPosition]
            if (!activeItem || !overItem) {
              return
            }
            let targetView

            if (isBefore) {
              targetView = views[newPosition]
            } else if (!isBefore && newPosition !== views.length - 1) {
              targetView = views[newPosition + 1]
            }

            const currentViewAfter = currentPosition !== views.length - 1 ? views[currentPosition + 1] : undefined

            await updateViewPriority(
              activeItem.number,
              targetView?.id || '',
              targetView?.number,
              currentViewAfter?.number,
            )
          }) as any,
          items: views.map(view => ({
            title: view.name,
            id: view.id,
          })),
        }),
        [views, updateViewPriority, selectedTab],
      )}
    >
      <DragAndDrop.SortableMoveDialog
        returnFocusRef={returnRef}
        closeDialog={() => {
          close()
        }}
      />
    </DragAndDropContext.Provider>
  )
}

export type MoveTabDialogContextProps = {
  setMoveTabDialogProps: (props: MoveTabDialogProps | null) => void
}

export const MoveTabDialogContext = createContext<MoveTabDialogContextProps>({
  setMoveTabDialogProps: () => {},
})

export const useMoveTabDialog = () => {
  const {setMoveTabDialogProps} = useContext(MoveTabDialogContext)

  return {setMoveTabDialogProps}
}
