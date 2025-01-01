import {useState, useCallback, useEffect} from 'react'
import {getSelectedFullDiffHash, parseDiffHash} from '../helpers/document-hash-helpers'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

export function useSelectedDiffHash(): string {
  const [selectedPathDigest, setSelectedPathDigest] = useState<string>('')

  const onHashChange = useCallback(() => {
    const windowHash = parseDiffHash(ssrSafeLocation.hash ?? '') ?? ''
    const hashWithoutPrefix = windowHash.replace('diff-', '')
    setSelectedPathDigest(hashWithoutPrefix)
  }, [])

  useEffect(() => {
    window.addEventListener('hashchange', onHashChange)
    onHashChange() // Initialize on mount
    return () => {
      window.removeEventListener('hashchange', onHashChange)
    }
  }, [onHashChange])

  return selectedPathDigest
}

export function useSelectedFullDiffHash(): string {
  const [selectedFullDiffHash, setSelectedFullDiffHash] = useState<string>('')

  const onHashChange = useCallback(() => {
    setSelectedFullDiffHash(getSelectedFullDiffHash())
  }, [])

  useEffect(() => {
    window.addEventListener('hashchange', onHashChange)
    onHashChange() // Initialize on mount
    return () => {
      window.removeEventListener('hashchange', onHashChange)
    }
  }, [onHashChange])

  return selectedFullDiffHash
}
