import {useCallback, useEffect, useState} from 'react'
import {Button, Stack} from '@primer/react'
import {PlayIcon, SquareFillIcon} from '@primer/octicons-react'
import {MarkdownRenderer} from '../MarkdownRenderer'
import type {CopilotMarkdownExtension} from '../extension'

interface StreamingDemoMarkdownRendererProps {
  interval: number
  content: string
  chunkSizeWords: number
  extensions?: CopilotMarkdownExtension[]
}

export const StreamingDemoMarkdownRenderer = ({
  content,
  interval,
  chunkSizeWords,
  extensions,
}: StreamingDemoMarkdownRendererProps) => {
  const [markdown, setMarkdown] = useState<string>('')
  const [unstreamedWords, setUnstreamedWords] = useState<string[]>(content.split(' '))
  const [streaming, setStreaming] = useState<boolean>(false)

  const streamNextChunk = useCallback(() => {
    setMarkdown(prev => `${prev} ${unstreamedWords.slice(0, chunkSizeWords).join(' ')}`)
    setUnstreamedWords(unstreamedWords.slice(chunkSizeWords))
    if (unstreamedWords.length === 0) setStreaming(false)
  }, [unstreamedWords, chunkSizeWords])

  useEffect(() => {
    if (!streaming) return

    const timeout = setTimeout(streamNextChunk, interval)
    return () => clearTimeout(timeout)
  }, [streamNextChunk, interval, streaming])

  const reset = useCallback(() => {
    setMarkdown('')
    setUnstreamedWords(content.split(' '))
    setStreaming(false)
  }, [content])

  useEffect(reset, [reset])

  return (
    <>
      <Stack direction="horizontal" gap="normal" padding="normal">
        <Button variant="primary" onClick={() => setStreaming(true)} disabled={streaming} leadingVisual={PlayIcon}>
          Play
        </Button>
        <Button onClick={() => setStreaming(false)} disabled={!streaming} leadingVisual={SquareFillIcon}>
          Pause
        </Button>
        <Button onClick={() => streamNextChunk()}>Step</Button>
        <Button onClick={reset}>Reset</Button>
      </Stack>
      <MarkdownRenderer markdown={markdown} isStreaming={unstreamedWords.length > 0} extensions={extensions} />
    </>
  )
}
