import {uploadFile} from '@github-ui/comment-box/fileUpload'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {getActiveMessages} from '@github-ui/copilot-chat/utils/copilot-chat-subthreading-helpers'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {useMemo} from 'react'

export const useTransformCopilotImageURLsFunction = (
  draftIssueRepo: RepositoryPickerRepository$data | null | undefined,
): ((issueBody: string) => Promise<string>) | undefined => {
  const {messages} = useChatState()
  const activeMessages = getActiveMessages(messages)

  return useMemo(() => {
    if (draftIssueRepo == null) {
      return undefined
    }

    // Download chat attachment URL images, and re-upload them into the issue
    // and replace the chat image URLs with the new ones
    return async (issueBody: string): Promise<string> => {
      // The image alt tag might have been edited by user, but as long as they keep the
      // image URL pointing at chat attachment, we re-upload these
      // Supports environments inside github.com domain, e.g. review-lab
      // This supports current style (numbered) and future style (GUID) image links
      const imageRx = /(!\[.*\]\(https:\/\/(?:.+\.)?github\.com\/github-copilot\/chat\/attachments\/[0-9a-fA-F-]+\))/g

      // Find all unique URLs in the issue body and make a set
      const matches = issueBody.match(imageRx)
      const chatAttachmentURLs = new Set<string>()
      for (const match of matches || []) {
        // This regex must match the above one
        const url = match.match(/https:\/\/(?:.+\.)?github\.com\/github-copilot\/chat\/attachments\/[0-9a-fA-F-]+/)?.[0]
        if (url) {
          chatAttachmentURLs.add(url)
        }
      }

      if (chatAttachmentURLs.size > 0) {
        // Download all images into memory
        const getFilesPromises = Array.from(chatAttachmentURLs).map(async url => {
          // Note that our CSP only allows downloading from a few allowed domains, protecting us from
          // fetching outside of github
          const response = await fetch(url)
          // The below works for local development, to test that image can be read and uploaded
          // const response = await fetch('http://alambic.github.localhost/avatars/u/2?s=40')
          const blob = await response.blob()
          const extension = blob.type.split('/')[1]
          const filename = `copilot-image.${extension}`
          const imageBitmap = await createImageBitmap(blob)
          const width = imageBitmap.width
          imageBitmap.close()
          return {file: new File([blob], filename, {type: blob.type}), url, width}
        })
        const files = await Promise.all(getFilesPromises)

        // Reupload the images to the issue
        const uploadedFiles = await Promise.all(
          files.map(async file => {
            if (file) {
              return {
                uploadedFile: await uploadFile(file.file, draftIssueRepo.databaseId?.toString()),
                originalUrl: file.url,
                width: file.width,
              }
            }
          }),
        )

        // Replace the original ![anytext](image1) with <img alt="anytext" width="123" src="newURL" />
        for (const file of uploadedFiles) {
          if (file) {
            const {uploadedFile, originalUrl, width} = file
            const newURL = uploadedFile.url
            if (newURL) {
              const regex = new RegExp(`!\\[(.*?)\\]\\(${originalUrl}\\)`, 'g')
              // eslint-disable-next-line github/unescaped-html-literal
              issueBody = issueBody.replace(regex, `<img alt="$1" width="${width}" src="${newURL}" />`)
            }
          }
        }

        sendEvent('dotcom_chat.activate', {
          target: 'BROWSER_ISSUE_CREATED_IMAGES',
          mode: 'immersive',
          imageCount: chatAttachmentURLs.size,
          threadId: activeMessages[0]?.threadID,
        })
      }

      return issueBody
    }
  }, [activeMessages, draftIssueRepo])
}
