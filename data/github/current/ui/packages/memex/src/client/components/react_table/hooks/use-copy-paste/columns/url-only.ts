import type {TableDataType} from '../../../table-data-type'
import {ClipboardOnly_UrlColumnModel} from '../constants'
import type {ClipboardColumnBehavior, ClipboardEntry} from '../types'

export const behavior: ClipboardColumnBehavior<typeof ClipboardOnly_UrlColumnModel> = {
  readContent: (row: TableDataType): ClipboardEntry => {
    const url = row.getUrl()
    return {
      text: url,
      dataType: ClipboardOnly_UrlColumnModel.dataType,
      value: url,
    }
  },
}
