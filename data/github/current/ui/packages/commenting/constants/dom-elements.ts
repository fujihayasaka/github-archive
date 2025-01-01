export const CLASS_NAMES = {
  issueComment: 'react-issue-comment',
  commentsContainer: 'react-comments-container',
  markdownBody: 'markdown-body',
  issueBody: 'react-issue-body',
}

export const IDS = {
  issueCommentComposer: 'react-issue-comment-composer',
}

export function withIDSelector(id: string) {
  return `#${id}`
}

export function getMostRelevantComposer(): HTMLElement | null {
  // If there is a comment composer inside the side panel, prioritize that
  const commentComposerInsideSidePanel = document.querySelector<HTMLElement>(
    `${withClassSelector(CLASS_NAMES.commentsContainer)} ${withIDSelector(
      IDS.issueCommentComposer,
    )}[data-inside-side-panel=true]`,
  )
  if (commentComposerInsideSidePanel) {
    return commentComposerInsideSidePanel
  }
  return document.querySelector<HTMLElement>(withIDSelector(IDS.issueCommentComposer))
}

export function withClassSelector(className: string) {
  return `.${className}`
}
