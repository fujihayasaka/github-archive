/**
 * This is a shim for the `@azure/search-documents` package. This package is dependent on browser globals, and is used
 * in such a way that it's effects are not needed for SSR. This shim is injected via webpack
 **/
export class SearchClient {
  constructor(_endpoint: string, _indexName: string, _credential: string) {
    return
  }

  async search(_query: string, _options: object) {
    return {
      results: [],
    }
  }
}

export class AzureKeyCredential {
  constructor(_key: string) {
    return
  }
}
