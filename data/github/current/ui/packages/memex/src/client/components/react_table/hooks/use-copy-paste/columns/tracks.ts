import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {progressAsPercent} from '../../../../../helpers/parsing'
import type {TracksColumnModel} from '../../../../../models/column-model/system/tracks'
import {Resources} from '../../../../../strings'
import type {TableDataType} from '../../../table-data-type'
import type {ClipboardColumnBehavior} from '../types'

export const behavior: ClipboardColumnBehavior<TracksColumnModel> = {
  readContent: (row: TableDataType) => {
    const tracks = row.columns.Tracks
    if (!tracks || tracks.total === 0) return

    return {
      text: Resources.progressCount({percent: progressAsPercent(tracks), total: tracks.total}),
      dataType: MemexColumnDataType.Tracks,
      value: tracks,
    }
  },
}
