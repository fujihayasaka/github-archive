import type {ExecutionState} from '../state/pipes-state'
import type {Pipeline} from '../types/app'
import {setLoopThreadId} from '../utils/loop-thread-storage'
import {logWarning} from '../utils/console'

export type LoopVersion = 'latest' | 'draft'

export interface LoopOperationResult {
  success: boolean
  loop?: Pipeline
  error?: string
}

export interface PipesStorage {
  // Reading operations with version awareness
  getLoop(loopID: string, version: LoopVersion): Promise<Pipeline | null>
  getAllLoops(version: LoopVersion): Promise<Pipeline[]>

  // Writing operations (always to draft)
  createLoop(loopOrId: Pipeline | string): Promise<LoopOperationResult>
  updateLoop(loopID: string, updateFn: (existingLoop: Pipeline | null) => Pipeline): Promise<LoopOperationResult>
  deleteLoop(loopID: string): Promise<LoopOperationResult>

  // Save/revert operations
  saveLoop(loopID: string): Promise<LoopOperationResult>
  revertLoop(loopID: string): Promise<LoopOperationResult>

  // Execution state operations (unchanged)
  getExecutionState(pipelineID: string, iteration?: number): Promise<ExecutionState | null>
  updateExecutionState(pipelineID: string, iteration: number, state: ExecutionState): Promise<ExecutionState>
}

interface PipelineRecord {
  loopID: string
  pipeline: Pipeline | null
  draftPipeline: Pipeline | null
}

function isPipelineRecord(value: unknown): value is PipelineRecord {
  return !!value && typeof value === 'object' && 'loopID' in value && typeof value.loopID === 'string'
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
  private static readonly CURRENT_VERSION = 5

  // New abstracted methods
  async getLoop(loopID: string, version: LoopVersion): Promise<Pipeline | null> {
    const record = await this.getPipelineRecord(loopID)
    if (!record) return null

    return version === 'latest' ? record.pipeline : record.draftPipeline
  }

  async getAllLoops(version: LoopVersion): Promise<Pipeline[]> {
    const records = await this.getAllPipelineRecords()
    if (!records) return []

    return records
      .map(record => (version === 'latest' ? record.pipeline : record.draftPipeline))
      .filter((pipeline): pipeline is Pipeline => pipeline !== null)
  }

  async createLoop(loopOrId: Pipeline | string): Promise<LoopOperationResult> {
    try {
      let loop: Pipeline | null
      let loopID: string | null

      if (typeof loopOrId === 'string') {
        // Create a minimal pipeline with the provided ID
        loop = null
        loopID = loopOrId
      } else {
        // Use the provided pipeline object
        loop = loopOrId
        loopID = loop.id
      }

      const record: PipelineRecord = {
        loopID,
        pipeline: null,
        draftPipeline: loop ? {...loop} : null,
      }

      const result = await this.createPipelineRecord(record)
      return {
        success: true,
        loop: result?.draftPipeline || undefined,
      }
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      }
    }
  }

  async updateLoop(
    loopID: string,
    updateFn: (existingLoop: Pipeline | null) => Pipeline,
  ): Promise<LoopOperationResult> {
    try {
      const result = await this.updatePipelineRecord(loopID, record => {
        const updatedPipeline = updateFn(record.draftPipeline)
        return {
          ...record,
          draftPipeline: updatedPipeline,
        }
      })

      return {
        success: true,
        loop: result?.draftPipeline || undefined,
      }
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      }
    }
  }

  async deleteLoop(loopID: string): Promise<LoopOperationResult> {
    try {
      await this.deletePipeline(loopID)
      return {success: true}
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      }
    }
  }

  async saveLoop(loopID: string): Promise<LoopOperationResult> {
    try {
      const result = await this.updatePipelineRecord(loopID, record => {
        if (!record.draftPipeline) {
          throw new Error('No draft pipeline to save')
        }

        return {
          ...record,
          pipeline: {...record.draftPipeline},
        }
      })

      return {
        success: true,
        loop: result?.pipeline || undefined,
      }
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      }
    }
  }

  async revertLoop(loopID: string): Promise<LoopOperationResult> {
    try {
      const result = await this.updatePipelineRecord(loopID, record => {
        if (!record.pipeline) {
          throw new Error('No saved pipeline to revert to')
        }

        return {
          ...record,
          draftPipeline: {...record.pipeline},
        }
      })

      return {
        success: true,
        loop: result?.draftPipeline || undefined,
      }
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      }
    }
  }

  // Legacy methods - keeping for backward compatibility
  private async getPipelineRecord(loopID: string): Promise<PipelineRecord | null> {
    return this.withTransaction(
      IndexedDBPipesStorage.PIPELINES_STORE,
      'readonly',
      objectStore => objectStore.get(loopID),
      result => (isPipelineRecord(result) ? result : null),
    )
  }

  async getPipeline(loopID: string): Promise<PipelineRecord | null> {
    return this.getPipelineRecord(loopID)
  }

  async getAllPipelineRecords(): Promise<PipelineRecord[]> {
    return this.withTransaction(
      IndexedDBPipesStorage.PIPELINES_STORE,
      'readonly',
      objectStore => objectStore.getAll(),
      result => (Array.isArray(result) ? result.filter(p => (isPipelineRecord(p) ? p.pipeline : null)) : []),
    )
  }

  createPipelineRecord(record: PipelineRecord): Promise<PipelineRecord | null> {
    const updatedAt = new Date().toISOString()
    const storedPipeline = record.pipeline
      ? {
          ...record.pipeline,
          id: record.loopID,
          updatedAt,
        }
      : record.pipeline

    const storedDraftPipeline = record.draftPipeline
      ? {
          ...record.draftPipeline,
          id: record.loopID,
          updatedAt,
        }
      : record.draftPipeline

    const updatedRecord: PipelineRecord = {
      ...record,
      pipeline: storedPipeline,
      draftPipeline: storedDraftPipeline,
    }

    return this.withTransaction(
      IndexedDBPipesStorage.PIPELINES_STORE,
      'readwrite',
      objectStore => objectStore.put(updatedRecord),
      () => updatedRecord,
    )
  }

  async updatePipelineRecord(
    loopID: string,
    updateFn: (existingRecord: PipelineRecord) => PipelineRecord,
  ): Promise<PipelineRecord | null> {
    const db = await this.getDatabase()

    return new Promise((resolve, reject) => {
      const transaction = db.transaction(IndexedDBPipesStorage.PIPELINES_STORE, 'readwrite')
      transaction.oncomplete = () => db.close()
      transaction.onerror = () => reject(transaction.error)

      const objectStore = transaction.objectStore(IndexedDBPipesStorage.PIPELINES_STORE)
      const getRequest = objectStore.get(loopID)

      getRequest.onerror = () => reject(getRequest.error)
      getRequest.onsuccess = () => {
        const existingRecord = getRequest.result

        if (!isPipelineRecord(existingRecord)) {
          reject(new Error(`Pipeline with ID ${loopID} not found`))
          return
        }

        try {
          const updatedRecord = updateFn(existingRecord)

          const normalizedPipeline = updatedRecord.pipeline
            ? {
                ...updatedRecord.pipeline,
                id: loopID,
              }
            : updatedRecord.pipeline

          const storedDraftPipeline = updatedRecord.draftPipeline
            ? {
                ...updatedRecord.draftPipeline,
                id: loopID,
                updatedAt: new Date().toISOString(),
              }
            : updatedRecord.draftPipeline

          const recordToStore = {
            ...updatedRecord,
            pipeline: normalizedPipeline,
            draftPipeline: storedDraftPipeline,
          }

          const putRequest = objectStore.put(recordToStore)
          putRequest.onerror = () => reject(putRequest.error)
          putRequest.onsuccess = () => resolve(recordToStore)
        } catch (error) {
          reject(error)
        }
      }
    })
  }

  deletePipeline(loopID: string): Promise<string> {
    return this.withTransaction(
      IndexedDBPipesStorage.PIPELINES_STORE,
      'readwrite',
      objectStore => objectStore.delete(loopID),
      () => loopID,
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
      const request = indexedDB.open(IndexedDBPipesStorage.PIPES_DB, IndexedDBPipesStorage.CURRENT_VERSION)
      request.onerror = () => reject(request.error)
      request.onsuccess = () => resolve(request.result)
      request.onupgradeneeded = async (event: IDBVersionChangeEvent) => {
        try {
          await IndexedDBPipesStorage.handleDatabaseUpgrade(request.result, event)
        } catch (error) {
          reject(error)
        }
      }
    })
  }

  static async handleDatabaseUpgrade(db: IDBDatabase, event: IDBVersionChangeEvent): Promise<void> {
    const oldVersion = event.oldVersion

    // Apply upgrades sequentially to support upgrading across multiple versions
    // For example, if oldVersion is 2 and current is 4, we need to apply
    // upgrade steps for 2 -> 3, and 3 -> 4

    // version 0 indicates this is the initialization of the DB
    if (oldVersion === 0) {
      await IndexedDBPipesStorage.upgradeFromVersion0(db)
      return
    }

    // upgrading to include the updatedAt field
    if (oldVersion < 2) {
      await IndexedDBPipesStorage.upgradeFromVersion1(event)
    }

    // upgrading to key on loopID instead of threadID
    if (oldVersion < 3) {
      await IndexedDBPipesStorage.upgradeFromVersion2(event)
    }

    // upgrading to copy pipeline data into draftPipeline
    if (oldVersion < 4) {
      await IndexedDBPipesStorage.upgradeFromVersion3(event)
    }

    // upgrading to migrate thread IDs to local storage and remove threadID field
    if (oldVersion < 5) {
      await IndexedDBPipesStorage.upgradeFromVersion4(event)
    }
  }

  static upgradeFromVersion0(db: IDBDatabase): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        const pipelinesStore = db.createObjectStore(IndexedDBPipesStorage.PIPELINES_STORE, {keyPath: 'loopID'})
        pipelinesStore.createIndex('loopID', 'loopID', {unique: true})

        const executionStatesStore = db.createObjectStore(IndexedDBPipesStorage.EXECUTION_STORE, {
          keyPath: ['pipelineId', 'iteration'],
        })
        executionStatesStore.createIndex('pipelineId, iteration', ['pipelineId', 'iteration'], {unique: true})
        executionStatesStore.createIndex('pipelineId', 'pipelineId', {unique: false})
        resolve()
      } catch (error) {
        reject(error)
      }
    })
  }

  // Helper function to await all promises and resolve the outer promise
  private static async waitForAllAndResolve(
    promises: Array<Promise<void>>,
    resolve: () => void,
    reject: (error: unknown) => void,
  ): Promise<void> {
    try {
      await Promise.all(promises)
      resolve()
    } catch (error) {
      reject(error)
    }
  }

  static upgradeFromVersion1(event: IDBVersionChangeEvent): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!event.target) return resolve()
      const transaction = (event.target as IDBOpenDBRequest).transaction
      if (!transaction) return resolve()

      const objectStore = transaction.objectStore(IndexedDBPipesStorage.PIPELINES_STORE)
      const request = objectStore.openCursor()

      // Array to collect all update promises
      const updatePromises: Array<Promise<void>> = []

      // iterate through all existing records and add the updatedAt field
      request.onsuccess = function (successEvent) {
        const cursor = (successEvent.target as IDBRequest<IDBCursorWithValue>)?.result
        if (cursor) {
          try {
            const record = cursor.value

            if (record.pipeline) record.pipeline.updatedAt = new Date().toISOString()

            // Create a promise for this update operation
            const updatePromise = new Promise<void>((resolveUpdate, rejectUpdate) => {
              const updateRequest = cursor.update(record)
              updateRequest.onsuccess = () => resolveUpdate()
              updateRequest.onerror = () => rejectUpdate(updateRequest.error)
            })

            // Add the promise to our collection
            updatePromises.push(updatePromise)

            cursor.continue()
          } catch (error) {
            reject(error)
          }
        } else {
          // No more items, wait for all updates to complete
          IndexedDBPipesStorage.waitForAllAndResolve(updatePromises, resolve, reject)
        }
      }

      request.onerror = function () {
        reject(request.error)
      }
    })
  }

  static upgradeFromVersion2(event: IDBVersionChangeEvent): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (!event.target) return resolve()
      const transaction = (event.target as IDBOpenDBRequest).transaction
      if (!transaction) return resolve()

      // iterate through all existing records and add the updatedAt field.
      // this interface corresponds to the old version of the database.
      const oldData: Array<{
        threadID: string
        pipeline: Pipeline
      }> = []
      const oldStore = transaction.objectStore(IndexedDBPipesStorage.PIPELINES_STORE)

      const request = oldStore.openCursor()

      request.onsuccess = function (successEvent) {
        const cursor = (successEvent.target as IDBRequest<IDBCursorWithValue>)?.result
        if (cursor) {
          const record = cursor.value
          if (record?.pipeline && !record.pipeline.updatedAt) record.pipeline.updatedAt = new Date().toISOString()
          oldData.push(record)
          cursor.continue()
        } else {
          try {
            // First phase is complete - we've collected all data
            // Now delete the old object store and recreate it
            transaction.db.deleteObjectStore(IndexedDBPipesStorage.PIPELINES_STORE)
            const newStore = transaction.db.createObjectStore(IndexedDBPipesStorage.PIPELINES_STORE, {
              keyPath: 'loopID',
            })
            newStore.createIndex('loopID', 'loopID', {unique: true})

            const newData = oldData.map(item => ({
              loopID: item.pipeline.id,
              threadID: item.threadID,
              pipeline: item.pipeline,
            }))

            if (newData.length === 0) {
              // No data to migrate
              resolve()
              return
            }

            // Array to collect all put promises
            const putPromises: Array<Promise<void>> = []

            // Reinsert the old data
            for (const item of newData) {
              const putPromise = new Promise<void>((resolvePut, rejectPut) => {
                const putRequest = newStore.put(item)
                putRequest.onsuccess = () => resolvePut()
                putRequest.onerror = () => rejectPut(putRequest.error)
              })
              putPromises.push(putPromise)
            }

            // Wait for all put operations to complete
            IndexedDBPipesStorage.waitForAllAndResolve(putPromises, resolve, reject)
          } catch (error) {
            reject(error)
          }
        }
      }

      request.onerror = function () {
        reject(request.error)
      }
    })
  }

  static upgradeFromVersion3(event: IDBVersionChangeEvent): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (!event.target) return resolve()
      const transaction = (event.target as IDBOpenDBRequest).transaction
      if (!transaction) return resolve()

      const objectStore = transaction.objectStore(IndexedDBPipesStorage.PIPELINES_STORE)

      const request = objectStore.openCursor()

      // Array to collect all update promises
      const updatePromises: Array<Promise<void>> = []

      // iterate through all existing records and copy pipeline to draftPipeline if needed
      request.onsuccess = function (successEvent) {
        const cursor = (successEvent.target as IDBRequest<IDBCursorWithValue>)?.result
        if (cursor) {
          try {
            const record = cursor.value

            // Check if we need to make an update
            if (record.pipeline && !record.draftPipeline) {
              record.draftPipeline = {...record.pipeline}

              // Create a promise for this update operation
              const updatePromise = new Promise<void>((resolveUpdate, rejectUpdate) => {
                const updateRequest = cursor.update(record)
                updateRequest.onsuccess = () => resolveUpdate()
                updateRequest.onerror = error => rejectUpdate(error)
              })

              // Add the promise to our collection
              updatePromises.push(updatePromise)
            }

            cursor.continue()
          } catch (error) {
            reject(error)
          }
        } else {
          // No more records to process, wait for all updates to complete
          IndexedDBPipesStorage.waitForAllAndResolve(updatePromises, resolve, reject)
        }
      }

      request.onerror = function () {
        reject(request.error)
      }
    })
  }

  static upgradeFromVersion4(event: IDBVersionChangeEvent): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (!event.target) return resolve()
      const transaction = (event.target as IDBOpenDBRequest).transaction
      if (!transaction) return resolve()

      const objectStore = transaction.objectStore(IndexedDBPipesStorage.PIPELINES_STORE)

      const request = objectStore.openCursor()

      // Array to collect all update promises
      const updatePromises: Array<Promise<void>> = []

      // iterate through all existing records and migrate thread IDs to local storage
      request.onsuccess = function (successEvent) {
        const cursor = (successEvent.target as IDBRequest<IDBCursorWithValue>)?.result
        if (cursor) {
          try {
            const record = cursor.value

            // Migrate thread ID to local storage if it exists
            if (record.threadID && record.loopID) {
              try {
                setLoopThreadId(record.loopID, record.threadID)
              } catch (error) {
                // Log error but don't fail the migration
                logWarning('Failed to migrate thread ID to localStorage:', error)
              }
            }

            // Remove the threadID field from the record
            if ('threadID' in record) {
              delete record.threadID

              // Create a promise for this update operation
              const updatePromise = new Promise<void>((resolveUpdate, rejectUpdate) => {
                const updateRequest = cursor.update(record)
                updateRequest.onsuccess = () => resolveUpdate()
                updateRequest.onerror = error => rejectUpdate(error)
              })

              // Add the promise to our collection
              updatePromises.push(updatePromise)
            }

            cursor.continue()
          } catch (error) {
            reject(error)
          }
        } else {
          // No more records to process, wait for all updates to complete
          IndexedDBPipesStorage.waitForAllAndResolve(updatePromises, resolve, reject)
        }
      }

      request.onerror = function () {
        reject(request.error)
      }
    })
  }
}
