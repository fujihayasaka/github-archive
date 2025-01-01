import type {Author} from './workspace-editor-types'

export default function authorName(author?: Author) {
  return author?.displayLogin || 'User'
}
