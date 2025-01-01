import {CopilotAnimation} from '@github-ui/copilot-animation'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {SandboxView} from '@github-ui/sandbox-view'
import {useEffect, useState} from 'react'

import type {CopilotImmersivePayload} from '../../routes/payloads'
import type {File, ItemsMap, PreviewableContentIdentifier, VersionedItemsMap} from './content-preview-types'
import {useContentPreview} from './ContentPreviewContext'
import styles from './HtmlPreview.module.css'

/**
 * Extracts the referenced style file names from the HTML content.
 */
function getReferencedStyles(htmlContent: string) {
  // grab all link tags
  const styleTags = Array.from(htmlContent.matchAll(/<link([^>]+)>/g))
    .map(tag => tag[1])
    .filter(tag => tag !== undefined)

  const styleReferences = []
  for (const style of styleTags) {
    // filter out non-stylesheet links
    const rel = /rel\s*=\s*"([^"]+)"/.exec(style)?.[1]
    if (rel !== 'stylesheet') continue

    // grab the href
    const href = /href\s*=\s*"([^"]+)"/.exec(style)?.[1]
    if (!href) continue

    styleReferences.push(href)
  }

  return styleReferences
}

/**
 * Takes a file reference and maps it to the latest version of the file's content.
 */
function mapReferenceToFile(reference: string, items: ItemsMap, versionedItems: VersionedItemsMap): File | null {
  const version: PreviewableContentIdentifier = `file:${reference}`
  if (!versionedItems.has(version)) return null

  const itemVersions = versionedItems.get(version) ?? []
  const lastVersion = itemVersions[itemVersions.length - 1]
  if (!lastVersion) return null

  const itemToAdd = items.get(lastVersion)
  if (!itemToAdd || itemToAdd.type !== 'file') return null

  return itemToAdd
}

/**
 * Iterate through referenced scripts/styles and add the latest version and the contents of each into a single string.
 * Returns a string of all scripts and files, as well as a list of files referenced. Null values in the list of files
 * are references to files that do not (yet) exist.
 */
function extractReferencedResourcesContent(htmlContent: string, items: ItemsMap, versionedItems: VersionedItemsMap) {
  const referencedScriptNames = Array.from(htmlContent.matchAll(/<script.*?src="(.*?)"/g))
    .map(script => script[1])
    .filter(script => script !== undefined)
  const referencedScriptFiles = referencedScriptNames.map(script => mapReferenceToFile(script, items, versionedItems))

  const referencedStyleNames = getReferencedStyles(htmlContent) // /<link rel="stylesheet" href="([^"]+)"/g.exec(htmlContent) ?? []
  const referencedStyleFiles = referencedStyleNames.map(style => mapReferenceToFile(style, items, versionedItems))

  const inlineScripts = Array.from(htmlContent.matchAll(/<script(?![^>]*\bsrc=).*?>(.*?)<\/script>/gms))
    .map(script => script[1])
    .filter(script => script !== undefined)

  const scripts = [
    ...referencedScriptFiles.map(file => file?.value ?? ''),
    ...inlineScripts,
    `document.dispatchEvent(new Event("DOMContentLoaded"))`,
  ].join('\n')

  return {
    scripts,
    styles: referencedStyleFiles.map(file => file?.value ?? '').join('\n'),
    files: referencedScriptFiles.concat(referencedStyleFiles),
  }
}

export function HtmlPreview({file}: {file: File}) {
  const {previewUrl} = useAppPayload<CopilotImmersivePayload>()
  const {items, versionedItems} = useContentPreview()
  const {scripts, styles: stylesText, files} = extractReferencedResourcesContent(file.value, items, versionedItems)
  const [forceShow, setForceShow] = useState(false)
  const isLoading = (file.isStreaming || files.some(f => !f || f.isStreaming)) && !forceShow

  // purposefully run this on every render to reset the timer
  useEffect(() => {
    if (isLoading) {
      // if we go 3 seconds with no progress, go ahead and show the content
      const id = setTimeout(() => {
        setForceShow(true)
      }, 3000)
      return () => clearTimeout(id)
    }
  })

  if (isLoading) {
    return (
      <div className={styles.loadingContainer}>
        <div className={styles.loadingHead}>
          <CopilotAnimation animationType="thinking" loopAnimation />
        </div>
        <p className={styles.loadingText}>Preparing your preview&hellip;</p>
      </div>
    )
  } else {
    return (
      <SandboxView
        key={file.id}
        scripts={scripts}
        styles={stylesText}
        content={file.value}
        viewscreenUrl={previewUrl}
      />
    )
  }
}
