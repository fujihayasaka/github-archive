import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {getActiveMessages} from '@github-ui/copilot-chat/utils/copilot-chat-subthreading-helpers'
import type {MediaContentItem} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useMemo} from 'react'

import type {DraftIssue} from '../content-preview-types'

export function usePreProcessedNewIssue(newIssue: DraftIssue): DraftIssue {
  const {messages} = useChatState()
  const activeMessages = getActiveMessages(messages)
  const media = useMemo(() => activeMessages.flatMap(message => message.mediaContent || []), [activeMessages])

  // We replace the image placeholders in the issue body before sending it to the issue form to avoid
  // unnecessary versioning when comparing the raw body to the processed one.
  const updatedBody = useMemo(() => {
    // The below works for local development, to emulate real images being uploaded
    // It can be triggered by `Link to ![image1](image1)` in the chat
    // const media: Array<{chatAttachmentUrl: string}> = [
    //   {chatAttachmentUrl: 'https://github.com/github-copilot/chat/attachments/215'},
    //   {chatAttachmentUrl: 'https://github.com/github-copilot/chat/attachments/216'},
    //   {chatAttachmentUrl: 'https://github.com/github-copilot/chat/attachments/217'},
    // ]

    return replaceImagePlaceholders(newIssue.body, media)
  }, [newIssue.body, media])

  if (updatedBody === newIssue.body) {
    return newIssue
  }

  return {...newIssue, body: updatedBody}
}

// This is where we want to finalize the draft content received from Copilot message
// before we send it to the preview form for user to review or edit
function replaceImagePlaceholders(issueBody: string | undefined, media: MediaContentItem[]) {
  if (!issueBody) {
    return ''
  }

  // Find all markdown image links in form of ![anytext](image1)
  const matches = issueBody.match(/(!\[.*?\]\(image\d+\))/g)
  if (matches == null) {
    return issueBody
  }

  for (const match of matches) {
    const urlPlaceholderRegex = /\(image(\d+)\)/

    // The regex matches the above regex, so must always return a match
    const imageIdString = match.match(urlPlaceholderRegex)![1]!

    // Image numbers are 1-indexed
    const imageId = parseInt(imageIdString, 10)

    // Images are reverse numbered in model output, so that if there are multiple issues drafted
    // in the same thread, this logic only picks up the images above the issue being created
    // This also supports scenario where model can not accurately number the images due to long thread
    const imageIndex = media.length - imageId

    // chatAttachmentUrl is sometimes populated (e.g. for shared threads), but if it's not, we use the url
    const url = media[imageIndex]?.chatAttachmentUrl || media[imageIndex]?.url
    if (url) {
      // Keep the alt text, but replace the image1 with the chat attachment URL
      const updatedMarkdown = match.replace(urlPlaceholderRegex, `(${url})`)
      issueBody = issueBody.replace(match, updatedMarkdown)
    }
  }
  return issueBody
}
