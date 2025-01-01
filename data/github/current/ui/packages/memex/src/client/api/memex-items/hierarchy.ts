import type {SubIssueSidePanelItem as SubIssueItem} from '@github-ui/sub-issues/sub-issue-types'

import type {State, StateReason} from '../common-contracts'
import {ItemType} from './item-type'

export class SubIssueSidePanelItem {
  constructor(item: SubIssueItem) {
    this.id = item.id
    this.title = item.title
    this.number = item.number
    this.url = item.url
    this.state = item.state.toLocaleLowerCase() as State
    this.stateReason = item.stateReason?.toLocaleLowerCase() as StateReason
    this.owner = item.owner
    this.repo = item.repo
  }

  id: number
  title: string
  url: string
  state: State
  stateReason?: StateReason
  number: number
  owner: string
  repo: string

  public readonly isHierarchy = true
  public readonly contentType: ItemType = ItemType.Issue

  getRawTitle(): string {
    return this.title
  }

  getUrl(): string {
    return this.url
  }

  getItemIdentifier(): {number: number; repo: string; owner: string; type: 'Issue'} | undefined {
    return {number: this.number, repo: this.repo, owner: this.owner, type: 'Issue'}
  }

  itemId(): number {
    return this.id
  }

  getNameWithOwnerReference(): string {
    return `${this.owner}/${this.repo}#${this.number}`
  }

  getNameWithOwnerReferenceParam(): string {
    return `${this.owner}|${this.repo}|${this.number}`
  }
}
