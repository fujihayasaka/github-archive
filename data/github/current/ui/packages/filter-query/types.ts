interface FilterQuerySegment {
  type: 'filter'
  key: string
  values: string[]
  raw: string
  isNegated: boolean
}

interface TextQuerySegment {
  type: 'text'
  value: string
}

export type QuerySegment = FilterQuerySegment | TextQuerySegment
