import {verifiedFetch, verifiedFetchJSON} from '@github-ui/verified-fetch'
import {createContext, type PropsWithChildren, useCallback, useContext, useEffect, useMemo, useState} from 'react'

import {type DataType, parseData} from '../utilities/parse-data'
import {Service, useWorkbenchStore} from './WorkbenchStoreContext'

export interface ParsedTableDataType {
  table: string
  data: DataType
}

export interface DatabaseContextProps {
  runtimePermanentName: string
}

export interface DatabaseContextData {
  fetchAllData: () => Promise<void>
  updateKeyInDatabase: (tableName: string, tableData: DataType) => Promise<void>
  deleteKeyFromDatabase: (keyName: string) => Promise<void>
  resetDatabase: () => Promise<void>
  isFetchingData: boolean
  didErrorFetchingData: boolean
  currentData: ParsedTableDataType[]
}

export const DatabaseContext = createContext<DatabaseContextData | undefined>(undefined)

export const DatabaseProvider = ({runtimePermanentName, children}: PropsWithChildren<DatabaseContextProps>) => {
  const {onError, onSuccess} = useWorkbenchStore()

  const [isFetching, setIsFetching] = useState<boolean>(false)
  const [isError, setIsError] = useState<boolean>(false)
  const [currentData, setCurrentData] = useState<ParsedTableDataType[]>([])

  const fetchSpecificKey = useCallback(
    async (keyName: string) => {
      setIsFetching(true)
      try {
        const response = await verifiedFetch(`/copilot/spark/runtime/data/${runtimePermanentName}/${keyName}`)
        if (!response.ok) {
          setIsError(true)
          setIsFetching(false)
          return Promise.reject(new Error(`Failed to fetch specific key: response=[${response.status}]`))
        }

        const data = await response.text()

        setIsError(false)
        setIsFetching(false)
        return {
          table: keyName,
          data: parseData(data),
        }
      } catch (error) {
        setIsError(true)
        setIsFetching(false)
        return Promise.reject(new Error(`Failed to fetch specific key: ${error}`))
      } finally {
        setIsFetching(false)
      }
    },
    [runtimePermanentName],
  )

  const fetchAllData = useCallback(async () => {
    setIsFetching(true)
    try {
      const response = await verifiedFetchJSON(`/copilot/spark/runtime/data/${runtimePermanentName}`)
      if (!response.ok) {
        setIsFetching(false)
        setIsError(true)
        onError({service: Service.RUNTIME})
        return Promise.reject(new Error(`Failed to fetch list of keys: response=[${response.status}]`))
      }
      const allKeys = await response.json()
      // Now that we have all keys, we can fetch each key's data
      const fetchedData = await Promise.all<ParsedTableDataType>(allKeys.map(fetchSpecificKey))

      setIsError(false)
      setIsFetching(false)
      onSuccess({service: Service.RUNTIME})
      setCurrentData(fetchedData)
    } catch (error) {
      setIsError(true)
      return Promise.reject(new Error(`Failed to fetch all data from database: ${error}`))
    } finally {
      setIsFetching(false)
    }
  }, [runtimePermanentName, fetchSpecificKey, onSuccess, onError])

  const updateKeyInDatabase = useCallback(
    async (tableName: string, tableData: DataType) => {
      try {
        const response = await verifiedFetch(`/copilot/spark/runtime/data/${runtimePermanentName}/${tableName}`, {
          method: 'POST',
          body: JSON.stringify(tableData.data),
        })

        if (!response.ok) {
          return Promise.reject(new Error(`Failed to update key in database: response=[${response.status}]`))
        }

        setCurrentData(data => {
          return data?.some(item => item.table === tableName)
            ? data?.map(item => (item.table === tableName ? {...item, data: tableData} : item))
            : [...(data || []), {table: tableName, data: tableData}]
        })
      } catch (error) {
        return Promise.reject(new Error(`Failed to update key in database: ${error}`))
      }
    },
    [runtimePermanentName],
  )

  const deleteKeyFromDatabase = useCallback(
    async (keyName: string) => {
      try {
        const response = await verifiedFetchJSON(`/copilot/spark/runtime/data/${runtimePermanentName}/${keyName}`, {
          method: 'DELETE',
        })

        if (!response.ok) {
          return Promise.reject(new Error(`Failed to delete key from database: response=[${response.status}]`))
        }

        setCurrentData(prevData => prevData?.filter(item => item.table !== keyName))
      } catch (error) {
        return Promise.reject(new Error(`Failed to delete key from database: ${error}`))
      }
    },
    [runtimePermanentName],
  )

  const resetDatabase = useCallback(async () => {
    // Iterate over every table key and delete it
    const newData = [...currentData]
    try {
      for (const item of currentData) {
        const response = await verifiedFetchJSON(`/copilot/spark/runtime/data/${runtimePermanentName}/${item.table}`, {
          method: 'DELETE',
        })

        if (!response.ok) {
          return Promise.reject(new Error(`Failed to delete key from database: response=[${response.status}]`))
        }

        // Remove the item from the newData array
        newData.splice(
          newData.findIndex(data => data.table === item.table),
          1,
        )
      }
    } catch (error) {
      return Promise.reject(new Error(`Failed to delete key from database: ${error}`))
    } finally {
      setCurrentData(newData)
    }
  }, [currentData, runtimePermanentName])

  // Fetch all data when the provider mounts
  useEffect(() => {
    fetchAllData()
  }, [fetchAllData])

  const contextValue = useMemo(
    () =>
      ({
        fetchAllData,
        updateKeyInDatabase,
        deleteKeyFromDatabase,
        resetDatabase,
        isFetchingData: isFetching,
        didErrorFetchingData: isError,
        currentData,
      }) satisfies DatabaseContextData,
    [fetchAllData, updateKeyInDatabase, deleteKeyFromDatabase, resetDatabase, isFetching, isError, currentData],
  )

  return <DatabaseContext.Provider value={contextValue}>{children}</DatabaseContext.Provider>
}

export const useDatabaseContext = () => {
  const context = useContext(DatabaseContext)
  if (!context) {
    throw new Error('useDatabaseContext must be used within a DatabaseProvider')
  }
  return context
}
