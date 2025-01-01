/**
 * Fakes out webpack to think we're making a Worker in webpack-worker.
 */
export class FakeWorker {
  declare url: URL
  constructor(url: URL) {
    this.url = url
  }
}
