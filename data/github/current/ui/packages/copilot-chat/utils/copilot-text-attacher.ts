import {sendEvent} from '@github-ui/hydro-analytics'

import {makePlaceholderReference} from './copilot-chat-helpers'
import type {CopilotChatManager} from './copilot-chat-manager'
import type {ThreadScopedFileReference} from './copilot-chat-types'
import {languageMap} from './language-info'

const TEXT_ATTACHMENT_SIZE_LIMIT = 500 * 1024 // 500KB

// Fake mime type that indicates the source of the text is the clipboard
export const CLIPBOARD_MIME_TYPE = 'application/x.clipboard'

// This regex will allow up to 51ch to give the model a bit of room for not being very good at counting
// Sometimes the model wraps the name in backticks, so we allow for that too
const FILE_NAME_REGEX = /^\s*`?([\w-_]{3,40}\.\w{1,10})`?\s*$/

// Matches the max width of ReferenceToken in the text input
const PREFERRED_MAX_FILE_NAME_LENGTH = 20

export class CopilotTextAttacher {
  private manager: CopilotChatManager
  private existingFileNames: Set<string>

  public constructor(manager: CopilotChatManager, existingFileNames: Set<string> = new Set()) {
    this.manager = manager
    this.existingFileNames = existingFileNames
  }

  public static async isAttachable(file: File) {
    if (file.size > CopilotTextAttacher.getAttachmentSizeLimit()) return false

    const text = await file.text()
    return CopilotTextAttacher.isPlainText(text)
  }

  private static fileExtensionsCache: string | undefined
  public static getTextFileExtensions(): string {
    return (CopilotTextAttacher.fileExtensionsCache ??= Object.values(languageMap)
      .flatMap(l => l.extensions ?? [])
      .filter(ext => ext !== 'stl') // STL is a binary format
      .join(','))
  }

  public static getAttachmentSizeLimit(): number {
    return TEXT_ATTACHMENT_SIZE_LIMIT
  }

  /**
   * Heuristically detect if a string is plain text (as opposed to binary) by counting null bytes and non-ASCII
   * characters.
   */
  private static isPlainText(data: string) {
    const sampleSize = Math.min(data.length, 1000)
    let nullBytes = 0
    let nonAsciiChars = 0

    for (let i = 0; i < sampleSize; i++) {
      const charCode = data.charCodeAt(i)
      if (charCode === 0) {
        nullBytes++
      } else if (charCode < 32 || charCode > 126) {
        nonAsciiChars++
      }
    }

    const nullByteRatio = nullBytes / sampleSize
    const nonAsciiRatio = nonAsciiChars / sampleSize

    return nullByteRatio <= 0.1 && nonAsciiRatio <= 0.2
  }

  private async makeReference(file: File, namePromise?: Promise<string>): Promise<ThreadScopedFileReference> {
    const text = await file.text()

    const name = file.name || (namePromise ? await namePromise : await this.generateFileName(text, file.type))
    return this.makeReferenceSync(text, name)
  }

  private makeReferenceSync(text: string, name: string): ThreadScopedFileReference {
    const extension = name.split('.').pop()
    sendEvent('copilot.attach_pasted_file', {extension, characters: text.length})

    return {
      type: 'thread-scoped-file',
      name,
      text,
      language: '',
    }
  }

  public async addAttachment(
    file: File,
    namePromise?: Promise<string>,
    name?: string,
  ): Promise<ThreadScopedFileReference | undefined> {
    // Repeats the `isAttachable` checks, but here we show error messages to the user
    if (file.size > CopilotTextAttacher.getAttachmentSizeLimit()) {
      this.manager.addAmbientError('Attached text files must be smaller than 500KB')
      return
    }

    const text = await file.text()
    if (!CopilotTextAttacher.isPlainText(text)) {
      this.manager.addAmbientError(
        `"${file.name}" has an unsupported file type. Please try again with a plain text file`,
      )
      return
    }

    let reference: ThreadScopedFileReference | undefined

    if (name) {
      reference = this.makeReferenceSync(text, name)
      this.manager.addReference(reference, 'text-attacher')
    } else {
      const placeholder = makePlaceholderReference(file)
      this.manager.addReference(placeholder, 'text-attacher')
      this.manager.dispatch({type: 'WAITING_ON_ATTACHMENT', loading: true})

      try {
        reference = await this.makeReference(file, namePromise)
        this.manager.replaceReference(placeholder, reference)
      } catch {
        this.manager.addAmbientError('Failed to process file. Please try again.')
        this.manager.removeReference(placeholder)
      } finally {
        this.manager.dispatch({type: 'WAITING_ON_ATTACHMENT', loading: false})
      }
    }

    return reference
  }

  public async generateFileName(text: string, type: string): Promise<string> {
    const namingConventionPrompt =
      this.existingFileNames.size > 0
        ? `\n\nFollow the naming formats used by these existing files: ${Array.from(this.existingFileNames)
            .slice(0, 5)
            .join(', ')}`
        : ''

    const nameResponse = await this.manager.service.getSimpleCompletion(
      `Return a suitable filename for the following file contents.
      Follow the file naming conventions of the language and do not include any special characters except for period, underscore or hyphens.
      Try to limit the name to ${PREFERRED_MAX_FILE_NAME_LENGTH} characters or less.
      You MUST include the file extension. Include only the filename in your response and nothing else.${namingConventionPrompt}

File contents:
\`\`\`
${text}
\`\`\`
`,
    )
    const name = nameResponse.ok ? FILE_NAME_REGEX.exec(nameResponse.payload)?.[1] : null

    if (name) {
      sendEvent('copilot.generate_pasted_file_name.success')
    } else {
      sendEvent('copilot.generate_pasted_file_name.failure')
    }

    return this.uniqueFileName(name ?? this.defaultFileName(type))
  }

  private uniqueFileName(name: string): string {
    if (!this.existingFileNames.has(name)) {
      return name
    }

    const lastDotIndex = name.lastIndexOf('.')
    const hasExtension = lastDotIndex > 0 && lastDotIndex < name.length - 1

    const baseName = hasExtension ? name.substring(0, lastDotIndex) : name
    const extension = hasExtension ? name.substring(lastDotIndex) : ''

    let counter = 2
    while (this.existingFileNames.has(`${baseName}${counter}${extension}`)) {
      counter++
    }

    return `${baseName}${counter}${extension}`
  }

  private defaultFileName(mimeType: string) {
    switch (mimeType) {
      case CLIPBOARD_MIME_TYPE:
        return 'pasted.txt'
      default:
        return 'untitled.txt'
    }
  }
}
