import {AvatarStack} from '@primer/react'
import {GitHubAvatar} from '@github-ui/github-avatar'

function extractCommentAuthors(comments: CommentPreviews[]): Author[] {
  const uniqueAuthors = new Set<string>()
  const extractedAuthors = comments.reduce((authors, comment) => {
    if (comment?.author && !uniqueAuthors.has(comment.author.login)) {
      authors.push({
        avatarUrl: comment.author.avatarUrl,
        login: comment.author.login,
      })
      uniqueAuthors.add(comment.author.login)
    }

    return authors
  }, [] as Author[])

  return extractedAuthors ?? []
}

interface Author {
  avatarUrl: string
  login: string
}

export interface CommentPreviews {
  author?: Author | null
}

export function PreviewAuthors({comments}: {comments: CommentPreviews[]}) {
  const authors = extractCommentAuthors(comments)

  if (authors.length < 1) return null

  return (
    <AvatarStack>
      {authors.map(({login, avatarUrl}) => (
        <GitHubAvatar key={login} alt={login} size={18} src={avatarUrl} />
      ))}
    </AvatarStack>
  )
}
