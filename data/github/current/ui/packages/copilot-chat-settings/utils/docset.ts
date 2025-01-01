import type {DocsetRepo, SourceRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export function makeSourceRepos(docsetRepos: Array<Pick<DocsetRepo, 'databaseId' | 'owner' | 'paths'>>): SourceRepo[] {
  return docsetRepos.map(repo => ({
    id: repo.databaseId as number,
    ownerID: repo.owner.databaseId as number,
    paths: repo.paths,
  }))
}
