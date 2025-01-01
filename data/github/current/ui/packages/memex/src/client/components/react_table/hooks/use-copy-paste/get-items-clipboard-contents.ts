import {ItemType} from '../../../../api/memex-items/item-type'
import type {ColumnModel} from '../../../../models/column-model'
import type {MemexItemModel} from '../../../../models/memex-item-model'
import {ClipboardOnly_UrlColumnModel} from './constants'
import {getClipboardContentFromRowAndColumn} from './get-clipboard-content-from-row-and-column'
import {type ClipboardColumnModel, isClipboardColumnModel} from './types'

export const getItemsClipboardContents = (
  items: ReadonlyArray<MemexItemModel>,
  fields: ReadonlyArray<ClipboardColumnModel | ColumnModel>,
) =>
  items
    .filter(item => item.contentType !== ItemType.RedactedItem)
    .map(item =>
      fields.map(field => {
        if (field.dataType !== ClipboardOnly_UrlColumnModel.dataType && !isClipboardColumnModel(field)) {
          return undefined
        }
        return getClipboardContentFromRowAndColumn(field, item)
      }),
    )
