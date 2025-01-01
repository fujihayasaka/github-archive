import {IndexedDBPipesStorage} from '../pipes-storage'

describe('IndexedDBPipesStorage', () => {
  describe('handleDatabaseUpgrade', () => {
    // Mock upgrade functions
    beforeEach(() => {
      jest.spyOn(IndexedDBPipesStorage, 'upgradeFromVersion0').mockImplementation(() => Promise.resolve())
      jest.spyOn(IndexedDBPipesStorage, 'upgradeFromVersion1').mockImplementation(() => Promise.resolve())
      jest.spyOn(IndexedDBPipesStorage, 'upgradeFromVersion2').mockImplementation(() => Promise.resolve())
      jest.spyOn(IndexedDBPipesStorage, 'upgradeFromVersion3').mockImplementation(() => Promise.resolve())
      jest.spyOn(IndexedDBPipesStorage, 'upgradeFromVersion4').mockImplementation(() => Promise.resolve())
    })

    afterEach(() => {
      jest.restoreAllMocks()
    })

    it('calls only upgradeFromVersion0 when oldVersion is 0', async () => {
      const db = {} as IDBDatabase
      const event = {oldVersion: 0} as IDBVersionChangeEvent

      await IndexedDBPipesStorage.handleDatabaseUpgrade(db, event)

      expect(IndexedDBPipesStorage.upgradeFromVersion0).toHaveBeenCalledWith(db)
      expect(IndexedDBPipesStorage.upgradeFromVersion1).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion2).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion3).not.toHaveBeenCalled()
    })

    it('calls upgradeFromVersion1, upgradeFromVersion2, upgradeFromVersion3, upgradeFromVersion4 when oldVersion is 1', async () => {
      const db = {} as IDBDatabase
      const event = {oldVersion: 1} as IDBVersionChangeEvent

      await IndexedDBPipesStorage.handleDatabaseUpgrade(db, event)

      expect(IndexedDBPipesStorage.upgradeFromVersion0).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion1).toHaveBeenCalledWith(event)
      expect(IndexedDBPipesStorage.upgradeFromVersion2).toHaveBeenCalledWith(event)
      expect(IndexedDBPipesStorage.upgradeFromVersion3).toHaveBeenCalledWith(event)
      expect(IndexedDBPipesStorage.upgradeFromVersion4).toHaveBeenCalledWith(event)
    })

    it('calls upgradeFromVersion2, upgradeFromVersion3, upgradeFromVersion4 when oldVersion is 2', async () => {
      const db = {} as IDBDatabase
      const event = {oldVersion: 2} as IDBVersionChangeEvent

      await IndexedDBPipesStorage.handleDatabaseUpgrade(db, event)

      expect(IndexedDBPipesStorage.upgradeFromVersion0).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion1).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion2).toHaveBeenCalledWith(event)
      expect(IndexedDBPipesStorage.upgradeFromVersion3).toHaveBeenCalledWith(event)
      expect(IndexedDBPipesStorage.upgradeFromVersion4).toHaveBeenCalledWith(event)
    })

    it('calls only upgradeFromVersion3, upgradeFromVersion4 when oldVersion is 3', async () => {
      const db = {} as IDBDatabase
      const event = {oldVersion: 3} as IDBVersionChangeEvent

      await IndexedDBPipesStorage.handleDatabaseUpgrade(db, event)

      expect(IndexedDBPipesStorage.upgradeFromVersion0).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion1).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion2).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion3).toHaveBeenCalledWith(event)
      expect(IndexedDBPipesStorage.upgradeFromVersion4).toHaveBeenCalledWith(event)
    })

    it('calls only upgradeFromVersion4 when oldVersion is 4', async () => {
      const db = {} as IDBDatabase
      const event = {oldVersion: 4} as IDBVersionChangeEvent

      await IndexedDBPipesStorage.handleDatabaseUpgrade(db, event)

      expect(IndexedDBPipesStorage.upgradeFromVersion0).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion1).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion2).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion3).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion4).toHaveBeenCalledWith(event)
    })

    it('calls no upgrade functions when oldVersion is current version (5)', async () => {
      const db = {} as IDBDatabase
      const event = {oldVersion: 5} as IDBVersionChangeEvent

      await IndexedDBPipesStorage.handleDatabaseUpgrade(db, event)

      expect(IndexedDBPipesStorage.upgradeFromVersion0).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion1).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion2).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion3).not.toHaveBeenCalled()
      expect(IndexedDBPipesStorage.upgradeFromVersion4).not.toHaveBeenCalled()
    })
  })
})
