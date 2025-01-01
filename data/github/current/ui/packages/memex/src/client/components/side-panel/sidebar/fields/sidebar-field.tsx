import type {KeyboardEventHandler} from 'react'

import {ViewerPrivileges} from '../../../../helpers/viewer-privileges'
import type {ColumnModel} from '../../../../models/column-model'
import type {MemexItemModel} from '../../../../models/memex-item-model'
import {FieldValue} from './core'
import type {SidePaneSideBarItemValueType} from './types'

type SidebarFieldData<T extends SidePaneSideBarItemValueType, C extends ColumnModel> = {
  model: MemexItemModel
  columnModel: C
  content?: T
}

export type SidebarCustomFieldProps<T extends SidePaneSideBarItemValueType, C extends ColumnModel> = SidebarFieldData<
  T,
  C
> & {
  onSaved: () => void
  onKeyDown?: KeyboardEventHandler
}

export type SidebarFieldRendererProps<T extends SidePaneSideBarItemValueType, C extends ColumnModel> = SidebarFieldData<
  T,
  C
>

export type SidebarFieldEditorProps<T extends SidePaneSideBarItemValueType, C extends ColumnModel> = SidebarFieldData<
  T,
  C
> & {
  onSaved: () => void
  onKeyDown?: KeyboardEventHandler
}

type SidebarFieldsProps<T extends SidePaneSideBarItemValueType, C extends ColumnModel> = SidebarCustomFieldProps<
  T,
  C
> & {
  renderer: React.FC<SidebarFieldRendererProps<T, C>>
  editor: React.FC<SidebarFieldEditorProps<T, C>>
  onSaved: () => void
  onKeyDown?: KeyboardEventHandler
}

export const SidebarField = <T extends SidePaneSideBarItemValueType, C extends ColumnModel>({
  model,
  columnModel,
  content,
  onSaved,
  onKeyDown,
  renderer: Renderer,
  editor: Editor,
}: SidebarFieldsProps<T, C>) => {
  const {hasWritePermissions} = ViewerPrivileges()

  return hasWritePermissions ? (
    <Editor model={model} columnModel={columnModel} content={content} onSaved={onSaved} onKeyDown={onKeyDown} />
  ) : (
    <FieldValue>
      <Renderer model={model} columnModel={columnModel} content={content} />
    </FieldValue>
  )
}
