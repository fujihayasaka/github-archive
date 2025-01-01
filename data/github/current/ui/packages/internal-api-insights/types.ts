export type TraceData = TraceNode[]

export type TraceNode = {
  count: number
  [key: string]: string | number | object | boolean | TraceNode
}

export type QueryLog = {
  query: string
  digested_query?: string
  duration: number
  result?: number
  cluster_name?: string
  fallbacks?: string[]
  backtrace?: string[]
  verified_fetch?: boolean
  path?: string
  onPrimary?: boolean
}

export type GroupedLogs = {[key: string]: QueryLog[]}
