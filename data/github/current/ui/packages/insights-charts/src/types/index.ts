import type {DataSetConfig} from '../../shared/base-chart/config'
import type {SeriesTableElement} from '../series-table-element'

export const SeriesType = {
  Time: 'time',
  Categorical: 'categorical',
} as const

export type SeriesType = (typeof SeriesType)[keyof typeof SeriesType]
export type SeriesDataItem = [string, number | null, string?]
export type SeriesData = SeriesDataItem[]

export interface SeriesColumn {
  name: string
  dataType: string
}

export interface Series {
  columns: SeriesColumn[]
  rows: SeriesData
  isSensitive: boolean
}

export interface ColorCodingConfig {
  [key: string]: DataSetConfig
}

export type Datelike = Date | number | string

declare global {
  interface HTMLElementTagNameMap {
    'series-table': SeriesTableElement
  }
}
