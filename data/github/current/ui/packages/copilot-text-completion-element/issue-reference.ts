export class IssueReference {
  private reference: string
  private _href: string | undefined
  private _baseUrl?: {origin: string; pathname: string}

  title: string | undefined
  description: string | undefined

  constructor(reference: string, baseUrl?: {origin: string; pathname: string}) {
    this.reference = reference
    this._baseUrl = baseUrl
  }

  private get baseUrl(): {origin: string; pathname: string} {
    if (!this._baseUrl) {
      this._baseUrl = {
        origin: window.location.origin,
        pathname: window.location.pathname,
      }
    }
    return this._baseUrl
  }

  get href(): string {
    if (!this._href) {
      if (this.reference.startsWith(this.baseUrl.origin)) {
        this._href = this.reference.replace(this.baseUrl.origin, `${this.baseUrl.origin}/ghost_pilot`)
        return this._href
      }

      const currentNwo = this.baseUrl.pathname.split('/').slice(1, 3).join('/')
      const [repo, issueNumber] = this.reference.split('#')

      if (this.reference.startsWith('#')) {
        this._href = `${this.baseUrl.origin}/ghost_pilot/${currentNwo}/issues/${issueNumber}`
      } else {
        this._href = `${this.baseUrl.origin}/ghost_pilot/${repo}/issues/${issueNumber}`
      }
    }

    return this._href
  }
}
