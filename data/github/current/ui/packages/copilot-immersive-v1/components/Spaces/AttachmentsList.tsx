import {generateGitHubFileMetadata} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import type {
  CustomCopilotFreeTextResource,
  CustomCopilotResource,
  CustomCopilotUploadedTextFileResource,
} from '@github-ui/custom-copilots/types'
import {clsx} from 'clsx'

import {AttachmentIcon} from './AttachmentIcon'
import styles from './AttachmentsList.module.css'

interface AttachmentsListProps {
  attachments: CustomCopilotResource[]
  onTextFileClick: (attachment: CustomCopilotFreeTextResource | CustomCopilotUploadedTextFileResource) => void
}

export function AttachmentsList({attachments, onTextFileClick}: AttachmentsListProps) {
  return (
    <ul className={styles.attachmentList}>
      {attachments.map(attachment => (
        <AttachmentItem key={attachment.id} attachment={attachment} onTextFileClick={onTextFileClick} />
      ))}
    </ul>
  )
}

interface AttachmentItemProps {
  attachment: CustomCopilotResource
  onTextFileClick: (attachment: CustomCopilotFreeTextResource | CustomCopilotUploadedTextFileResource) => void
}

function AttachmentItem({attachment, onTextFileClick}: AttachmentItemProps) {
  switch (attachment.type) {
    case 'github_file': {
      const {filePath, fileName, fileUrl} = generateGitHubFileMetadata(attachment)

      return (
        <li key={attachment.id} className={styles.attachmentItem}>
          <a className={styles.attachmentItemLink} href={fileUrl} rel="noopener noreferrer" target="_blank">
            <div className={styles.attachmentIcon}>
              <AttachmentIcon attachment={attachment} />
            </div>

            <div className={styles.attachmentText}>
              <div className={styles.attachmentName}>{fileName}</div>
              <p className={styles.attachmentContent}>{filePath}</p>
            </div>
          </a>
        </li>
      )
    }
    case 'free_text':
    case 'uploaded_text_file':
      return (
        <li key={attachment.id} className={styles.attachmentItem}>
          <button type="button" onClick={() => onTextFileClick(attachment)} className={styles.attachmentItemButton}>
            <span className={styles.attachmentItemLink}>
              <div className={styles.attachmentIcon}>
                <AttachmentIcon attachment={attachment} />
              </div>

              <div className={styles.attachmentText}>
                <div className={clsx(styles.attachmentName, styles.lineClamp)}>{attachment.name}</div>
                {'text' in attachment && (
                  <p className={clsx(styles.attachmentContent, styles.lineClamp)}>{attachment.text}</p>
                )}
              </div>
            </span>
          </button>
        </li>
      )
    case 'github_issue':
    case 'github_pull_request':
      return (
        <li key={attachment.id} className={styles.attachmentItem}>
          <a className={styles.attachmentItemLink} href={attachment.url} rel="noopener noreferrer" target="_blank">
            <div className={styles.attachmentIcon}>
              <AttachmentIcon attachment={attachment} className="fgColor-success" />
            </div>

            <div className={styles.attachmentText}>
              <div className={clsx(styles.attachmentName, styles.lineClamp)}>
                {attachment.title}&nbsp;
                <span className="fgColor-muted text-light">{`#${attachment.number}`}</span>
              </div>
              <div className={clsx(styles.attachmentContent, styles.lineClamp)}>{attachment.nwo}</div>
            </div>
          </a>
        </li>
      )
    default:
      return null
  }
}
