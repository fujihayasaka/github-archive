import path, {relative as relativePath} from 'path'

export const STORYBOOK_URL = `http://127.0.0.1:6006/index.json`

/**
 * @interface
 */
export class ILocationFinder {
  /**
   * @abstract
   * @returns {Promise<void>}
   */
  init() {}
  /**
   * @abstract
   * @param {string} baseDirectory
   * @param {string} location
   * @returns {string}
   */
  // eslint-disable-next-line unused-imports/no-unused-vars
  find(baseDirectory, location) {}
}

/**
 * @implements {ILocationFinder}
 */
export class JestLocationFinder {
  async init() {}

  /** @type {(baseDirectory: string, location: string) => string} */
  find(baseDirectory, location) {
    return relativePath(baseDirectory, location)
  }
}

export class StorybookLocationFinder {
  /** @type {any} */
  stories = {}

  async init() {
    try {
      this.stories = await this.fetchStories()
    } catch (error) {
      console.error(`There was an error when fetching the stories from Storybook: ${error.message}`)
    }
  }

  /** @type {(baseDirectory: string, location: string) => string} */
  find(baseDirectory, location) {
    return this.findStorybookLocation(relativePath(baseDirectory, location))
  }

  /** @type {(relativeLocation: string) => string} */
  findStorybookLocation(relativeLocation) {
    const storyPath = this.extractStoryPath(relativeLocation)

    if (!this.stories.entries) {
      console.log(`The fetched stories are not valid`)
      return `${storyPath}.test.js`
    }

    for (const key of Object.keys(this.stories.entries)) {
      if (key.startsWith(storyPath)) {
        const importPath = this.stories.entries[key].importPath
        return importPath.startsWith('./') ? importPath.slice(2) : importPath
      }
    }
    return ''
  }

  /** @type {(location: string) => string} */
  extractStoryPath(location) {
    /**
     * Extracts the name from a temporal file:
     * from the following temporal file name: ../../tmp/887d1aadfb5d5aec47067e358b699c86/recipes-filter-interactions-advanced-filter-dialog.test.js:373
     * extracts: recipes-filter-interactions-advanced-filter-dialog
     */
    return path.basename(location).replace(/\.test\.js:.+$/, '')
  }

  /** @type {() => Promise<string>} */
  async fetchStories() {
    const response = await global.fetch(STORYBOOK_URL)

    if (!response.ok) {
      throw new Error(`There was an ${response.status} HTTP status code when fetching the stories from Storybook`)
    }

    return await response.json()
  }
}
