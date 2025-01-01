import {noop} from '@github-ui/noop'
import type {Dispatch, PropsWithChildren, SetStateAction} from 'react'
import {createContext, useContext, useMemo, useState} from 'react'

type NestedListItemControlsDialogContextProps = {
  controlsDialogOpen: boolean
  setControlsDialogOpen: Dispatch<SetStateAction<boolean>>
}

const NestedListItemControlsDialogContext = createContext<NestedListItemControlsDialogContextProps>({
  controlsDialogOpen: false,
  setControlsDialogOpen: noop,
})

export const NestedListItemControlsDialogProvider = ({children}: PropsWithChildren) => {
  const [controlsDialogOpen, setControlsDialogOpen] = useState(false)
  const contextProps = useMemo(() => ({controlsDialogOpen, setControlsDialogOpen}), [controlsDialogOpen])
  return (
    <NestedListItemControlsDialogContext.Provider value={contextProps}>
      {children}
    </NestedListItemControlsDialogContext.Provider>
  )
}

export const useNestedListItemControlsDialog = () => {
  return useContext(NestedListItemControlsDialogContext)
}
