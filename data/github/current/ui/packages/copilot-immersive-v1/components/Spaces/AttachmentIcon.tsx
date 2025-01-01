import type {CustomCopilotResource} from '@github-ui/custom-copilots/types'
import {FileAddedIcon, FileIcon, GitPullRequestIcon, IssueOpenedIcon, PasteIcon} from '@primer/octicons-react'

interface AttachmentIconProps {
  attachment: CustomCopilotResource
  className?: string
}

export function AttachmentIcon({attachment, className}: AttachmentIconProps) {
  switch (attachment.type) {
    case 'github_file':
      return <FileIcon className={className} />
    case 'free_text':
      return <PasteIcon className={className} />
    case 'uploaded_text_file':
      // TODO: Consider using a more specific icon for uploaded text files - https://github.com/github/copilot-productivity/issues/6011
      return <FileAddedIcon className={className} />
    case 'github_issue':
      return <IssueOpenedIcon className={className} />
    case 'github_pull_request':
      return <GitPullRequestIcon className={className} />
    default:
      return null
  }
}
