import type {SafeHTMLString} from '@github-ui/safe-html'
import {useSyncedState} from '@github-ui/use-synced-state'
import DOMPurify from 'dompurify'
import hljs from 'highlight.js'
import {Marked} from 'marked'
import {markedHighlight} from 'marked-highlight'
import {useMemo} from 'react'

/**
 * The `value` prop passed from the Editor component comes from a stable callback to avoid re-rendering
 * the FileContext and entire react tree on every keystroke. This means that the value will always be the same
 * while a user is typing.
 *
 * Specifically for a markdown editor, where we want to support live updates and previews, we want to set our own
 * `previewRawValue` state so that the previews stay up-to-date with the user-inputted value. We use local state
 * to ensure that only this component re-renders when the value changes.
 */
export function useMarkdownPreview(initialValue: string, ownerLogin: string, repoName: string, headBranch: string) {
  const [previewRawValue, setPreviewRawValue] = useSyncedState(initialValue)
  const previewContent = useMemo(() => {
    const renderer = new Marked(
      {gfm: true},
      markedHighlight({
        langPrefix: 'hljs language-',
        highlight(code) {
          return hljs.highlightAuto(code).value
        },
      }),
    )

    const unsafeHTML = renderer.parse(previewRawValue || '') as string
    const purify = DOMPurify()

    purify.addHook('afterSanitizeAttributes', node => {
      if (node.nodeName !== 'IMG') return
      processRelativeImagePaths(node, `${ownerLogin}/${repoName}`, headBranch)
    })
    return purify.sanitize(unsafeHTML) as SafeHTMLString
  }, [headBranch, ownerLogin, previewRawValue, repoName])

  const updatePreviewContent = (val: string) => {
    setPreviewRawValue(val)
  }

  return {previewContent, updatePreviewContent}
}

export function processRelativeImagePaths(imgNode: Element, repository: string, headBranch: string) {
  const URL_SCHEME_REGEX = /^[a-z][a-z0-9+\-.]+:/i
  const PROTOCOL_SCHEME_REGEX = /^\/\//i
  const HASH_SCHEME_REGEX = /^#/

  // Only process relative URLs. Ignore absolute URLs (e.g. "https://"), protocol-relative URLs (e.g. "//"), and html anchors (e.g. "#").
  function makeRelative(url: string) {
    if (!url) return null
    if (URL_SCHEME_REGEX.test(url) || PROTOCOL_SCHEME_REGEX.test(url) || HASH_SCHEME_REGEX.test(url)) return

    return correctedLink(url)
  }

  // Format the link based on what branch the image is in relative to the PR's branch.
  // There are three cases:
  // 1. The image is in the current branch
  //    i.e. ![alt text](assets/images/image.png)
  // 2. The image is in the PR's base branch
  //    i.e. ![alt text](/../branch-name/assets/images/image.png)
  // 3. The image is in some other branch
  //    i.e. ![alt text](/../../branch-name/assets/images/image.png)
  //
  // Note: There is an edge case in case #3 that we are not handling.
  //   If a PR part of a chain of several PRs, and the image is added in a branch that is neither the PR's base branch
  //   nor the repository's default branch, we have no way of accessing the branch name from the client.
  //   For example, if the PR chain is:
  //     main -> branch1 -> branch2 -> branch3
  //   The PR for branch 3 can successfully access images in branch2 or in main, but not in branch1.
  //   In this case, we will default to looking for the image in the repos default branch, but it will not
  //   render correctly in the preview. It will render correctly in a context using the server-side markdown pipeline.
  function correctedLink(url: string) {
    const urlParts = url.split('/').map(encodeURIComponent)
    const usableUrl = urlParts.filter(i => !!i && i !== '..').join('/')
    const parentDirectoryCount = urlParts.reduce(
      (count, currentString) => (currentString === '..' ? count + 1 : count),
      0,
    )

    switch (parentDirectoryCount) {
      // The image is in the current branch.
      case 0:
        return `/${repository}/blob/${headBranch}/${usableUrl}`
      // The image is in the base branch
      case 1:
        return `/${repository}/blob/${usableUrl}`
      // Assume the image is in the default branch
      default:
        return `/${repository}/blob/${usableUrl}`
    }
  }

  // Replace `blob` with `raw` in the URL
  // Epecially helpful for private repositories, where the raw image URL gets redirected to
  // raw.githubusercontent.com with a token that expires.
  function makeRawUrl(url: string | null) {
    if (!url) return null
    const BLOB_URL = new RegExp(`^(/[^/]+/[^/]+/blob/)(.*)$`)
    const match = url.match(BLOB_URL)
    if (match) {
      return `${match[1]?.replace('/blob/', '/raw/')}${match[2]}`
    }
    return null
  }

  function applyFilter(node: Element) {
    const imageSrc = node.getAttribute('src')
    if (!imageSrc) return
    const newUrl = makeRelative(imageSrc)
    if (newUrl) {
      node.setAttribute('src', newUrl)
    }
  }

  applyFilter(imgNode)

  const rawUrl = makeRawUrl(imgNode.getAttribute('src'))
  if (rawUrl) {
    imgNode.setAttribute('src', rawUrl)
  }
}
