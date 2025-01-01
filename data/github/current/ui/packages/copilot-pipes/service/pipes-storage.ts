import type {ExecutionState} from '../state/pipes-state'
import type {Pipeline} from '../types/app'

export interface PipesStorage {
  getPipeline(threadID: string): Promise<Pipeline | null>
  updatePipeline(threadID: string, pipeline: Pipeline): Promise<Pipeline>
  getExecutionState(pipelineID: string, iteration?: number): Promise<ExecutionState | null>
  updateExecutionState(pipelineID: string, iteration: number, state: ExecutionState): Promise<ExecutionState>
}

interface PipelineRecord {
  threadID: string
  pipeline: Pipeline
}

function isPipelineRecord(value: unknown): value is PipelineRecord {
  return (
    !!value &&
    typeof value === 'object' &&
    'threadID' in value &&
    typeof value.threadID === 'string' &&
    'pipeline' in value &&
    typeof value.pipeline === 'object'
  )
}

interface ExecutionStateRecord {
  pipelineId: string
  iteration: number
  executionState: ExecutionState
}

function isExecutionStateRecord(value: unknown): value is ExecutionStateRecord {
  return (
    !!value &&
    typeof value === 'object' &&
    'pipelineId' in value &&
    typeof value.pipelineId === 'string' &&
    'iteration' in value &&
    typeof value.iteration === 'number' &&
    'executionState' in value &&
    typeof value.executionState === 'object'
  )
}

export class IndexedDBPipesStorage implements PipesStorage {
  private static PIPES_DB = 'copilot-pipes'
  private static PIPELINES_STORE = 'pipelines'
  private static EXECUTION_STORE = 'executionStates'

  async getPipeline(threadID: string): Promise<Pipeline | null> {
    return this.withTransaction(
      IndexedDBPipesStorage.PIPELINES_STORE,
      'readonly',
      objectStore => objectStore.get(threadID),
      result => (isPipelineRecord(result) ? result.pipeline : null),
    )
  }

  updatePipeline(threadID: string, pipeline: Pipeline): Promise<Pipeline> {
    return this.withTransaction(
      IndexedDBPipesStorage.PIPELINES_STORE,
      'readwrite',
      objectStore => objectStore.put({threadID, pipeline}),
      () => pipeline,
    )
  }

  getExecutionState(pipelineID: string, iteration?: number): Promise<ExecutionState | null> {
    if (iteration !== undefined) {
      return this.withTransaction(
        IndexedDBPipesStorage.EXECUTION_STORE,
        'readonly',
        objectStore => objectStore.get([pipelineID, iteration]),
        result => (isExecutionStateRecord(result) ? result.executionState : null),
      )
    } else {
      return this.withTransaction(
        IndexedDBPipesStorage.EXECUTION_STORE,
        'readonly',
        objectStore => objectStore.index('pipelineId').getAll(pipelineID),
        result => {
          if (!Array.isArray(result)) return null
          const states = result.filter(isExecutionStateRecord)
          if (states.length === 0) return null
          const maxIteration = Math.max(...states.map(s => s.iteration))
          return states.find(s => s.iteration === maxIteration)?.executionState ?? null
        },
      )
    }
  }

  updateExecutionState(pipelineId: string, iteration: number, executionState: ExecutionState): Promise<ExecutionState> {
    return this.withTransaction(
      IndexedDBPipesStorage.EXECUTION_STORE,
      'readwrite',
      objectStore => objectStore.put({pipelineId, iteration, executionState}),
      () => executionState,
    )
  }

  private async withTransaction<T>(
    storeName: string,
    mode: IDBTransactionMode,
    execute: (store: IDBObjectStore) => IDBRequest,
    processResult: (result: unknown) => T,
  ): Promise<T> {
    const db = await this.getDatabase()

    return new Promise((resolve, reject) => {
      const transaction = db.transaction(storeName, mode)
      transaction.oncomplete = () => db.close()
      transaction.onerror = () => reject(transaction.error)

      const objectStore = transaction.objectStore(storeName)
      const request = execute(objectStore)
      request.onsuccess = () => resolve(processResult(request.result))
      request.onerror = () => reject(request.error)
    })
  }

  private getDatabase(): Promise<IDBDatabase> {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(IndexedDBPipesStorage.PIPES_DB)
      request.onerror = () => reject(request.error)
      request.onsuccess = () => resolve(request.result)
      request.onupgradeneeded = () => {
        const db = request.result

        const pipelinesStore = db.createObjectStore(IndexedDBPipesStorage.PIPELINES_STORE, {keyPath: 'threadID'})
        pipelinesStore.createIndex('threadID', 'threadID', {unique: true})

        const executionStatesStore = db.createObjectStore(IndexedDBPipesStorage.EXECUTION_STORE, {
          keyPath: ['pipelineId', 'iteration'],
        })
        executionStatesStore.createIndex('pipelineId, iteration', ['pipelineId', 'iteration'], {unique: true})
        executionStatesStore.createIndex('pipelineId', 'pipelineId', {unique: false})
      }
    })
  }
}
