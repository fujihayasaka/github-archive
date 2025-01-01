import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'
import {http, HttpResponse} from 'msw'
import {DatabaseContext, type DatabaseContextData} from '../DatabaseContext'
import type {DatabaseMock} from '../../utilities/parse-data'

export const databaseContextDecoratorArgTypes = {
  isFetchingData: {
    control: 'boolean',
    description: 'Is data currently being fetched?',
  },
  didErrorFetchingData: {
    control: 'boolean',
    description: 'Did an error occur while fetching data?',
  },
  currentData: {
    table: {
      disable: true,
    },
  },
}

export const databaseContextDecoratorArgs = {
  isFetchingData: false,
  didErrorFetchingData: false,
  currentData: [],
}

export const withDatabaseContext: Decorator = (Story, {args}) => {
  const contextValue = {
    fetchAllData: async () => {await action('fetchAllData')},
    updateKeyInDatabase: async () => {await action('updateKeyInDatabase')},
    deleteKeyFromDatabase: async () => {await action('deleteKeyFromDatabase')},
    resetDatabase: async () => {await action('resetDatabase')},
    isFetchingData: args.isFetchingData as boolean,
    didErrorFetchingData: args.didErrorFetchingData as boolean,
    currentData: args.currentData as DatabaseContextData['currentData'],
  } satisfies DatabaseContextData

  return (
    <DatabaseContext.Provider value={contextValue}>
      <Story />
    </DatabaseContext.Provider>
  )
}

export const transformDatabaseToMockResponses = (db: DatabaseMock, databaseId: string) => {
  return [
    // Create one endpoint to get the full list of keys in the database
    http.get(`/copilot/spark/runtime/data/${databaseId}`, () => {
      return HttpResponse.json(Object.keys(db))
    }),

    // Then create endpoints for each key in the database
    ...Object.entries(db).flatMap(([key]) => [
      http.get(`/copilot/spark/runtime/data/${databaseId}/${key}`, () => {
        return HttpResponse.json(db[key])
      }),
      http.post(`/copilot/spark/runtime/data/${databaseId}/${key}`, data => {
        db[key] = data
        return HttpResponse.json(data)
      }),
      http.delete(`/copilot/spark/runtime/data/${databaseId}/${key}`, () => {
        action('deleteKey')(key)
        delete db[key]
        return HttpResponse.json()
      }),
    ]),
  ]
}
