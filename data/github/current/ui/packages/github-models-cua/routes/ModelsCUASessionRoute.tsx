import {Button, LinkButton, Spinner, TextInput} from '@primer/react'
import {useSession} from '../components/cua/UseSession'
import {appBuilder} from '../config/app'
import type {StepMessage} from '../types'
import {useSearchParams} from '@github-ui/use-navigate'
import {useCallback, useEffect, useRef, useState} from 'react'
import {ArrowLeftIcon, MarkGithubIcon} from '@primer/octicons-react'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'

export const modelsCUASessionRoute = appBuilder.createQueryRouteConfig('modelsCUASessionRoute', {
  path: '/models/cua/session',
  index: true,
})

const userInstructions = (
  url: string,
) => `You are now a web tester, and your job is to provide a final feedback on reviewing an on-going website. Please test page '${url}'.
Important: Please conclude your feedback in the end, according to the guideline format.
`

export default function Page() {
  const [searchParams] = useSearchParams()
  const url = searchParams.get('url') || ''
  const prompt = searchParams.get('prompt') || ''

  const {steps, loading} = useSession(`${prompt}\n${userInstructions(url)}`, 100)

  const messages = steps.filter(
    item => item.content.content_type === 'text' && item.content.parts[0] && item.content.parts[0][0] !== '{',
  )
  const screenshots = steps.filter(item => item.content.content_type === 'computer_output')
  const [selectedScreenshot, setSelectedScreenshot] = useState(undefined as string | undefined)
  const screenshot = selectedScreenshot || getImageData(screenshots[screenshots.length - 1])

  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const screenshotsContainerRef = useRef<HTMLDivElement>(null)

  const scrollMessages = useCallback(() => {
    if (!messagesContainerRef.current) return // This is not expected
    messagesContainerRef.current.scrollTo(0, messagesContainerRef.current.scrollHeight)
  }, [])
  const scrollScreenshots = useCallback(() => {
    if (!screenshotsContainerRef.current) return // This is not expected
    screenshotsContainerRef.current.scrollTo(screenshotsContainerRef.current.scrollWidth, 0)
  }, [])

  useEffect(() => {
    requestAnimationFrame(scrollMessages)
  }, [messages, scrollMessages])
  useEffect(() => {
    requestAnimationFrame(scrollScreenshots)
  }, [screenshots, scrollScreenshots])

  return (
    <div
      className="d-flex flex-column gap-3 p-3 overflow-hidden"
      style={{
        height: 'calc(100vh - 64px)',
        maxHeight: 'calc(100vh - 64px)',
      }}
    >
      <div className="d-flex gap-2 flex-items-center flex-justify-between">
        <LinkButton
          href={`/models/cua?prompt=${encodeURIComponent(prompt)}&url=${encodeURIComponent(url)}`}
          leadingVisual={<ArrowLeftIcon />}
        >
          Start over
        </LinkButton>

        <div className="d-flex gap-2 flex-items-center">
          <div className="text-bold">URL</div>
          <TextInput value={url} disabled />
          <div className="text-bold">Prompt</div>
          <TextInput value={prompt} disabled />
        </div>
      </div>

      <div className="flex-1 d-flex gap-3 overflow-hidden">
        <div className="flex-1 d-flex gap-2 overflow-hidden flex-column border rounded-md">
          <div className="text-bold border-bottom p-2 bgColor-muted">Messages</div>
          <div className="flex-1 overflow-y-auto d-flex flex-column gap-2" ref={messagesContainerRef}>
            {messages.map(item => {
              if (item.content.content_type !== 'text') return null
              return (
                <div key={item.id} className="px-2">
                  <div className="d-flex gap-2 flex-items-center">
                    <MarkGithubIcon />
                    <span className="text-bold">Computer User Agent</span>
                  </div>
                  <MarkdownRenderer markdown={item.content.parts.join('\n')} />
                </div>
              )
            })}
            {loading && (
              <div className="d-flex flex-justify-center">
                <Spinner />
              </div>
            )}
          </div>
        </div>
        <div className="flex-1 border rounded-md d-flex flex-column overflow-hidden">
          <div className="text-bold border-bottom p-2 bgColor-muted">Screenshots</div>
          <div className="width-full overflow-x-auto d-flex gap-2 p-2" ref={screenshotsContainerRef}>
            {screenshots.map(item => {
              const screenshotContent = getImageData(item)
              return (
                <Button
                  variant="link"
                  key={item.id}
                  onClick={() => setSelectedScreenshot(screenshotContent)}
                  className="border color-shadow-medium cursor-pointer"
                >
                  <img style={{width: '96px'}} alt="CUA Screenshot" src={screenshotContent} />
                </Button>
              )
            })}
          </div>
          {screenshot ? (
            <img className="m-2 color-shadow-medium" alt="CUA Screenshot" src={screenshot} />
          ) : (
            <div className="d-flex flex-justify-center">
              <Spinner />
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

const getImageData = (item: StepMessage | undefined) => {
  if (item && item.content?.content_type === 'computer_output') {
    const screenshot = item.content?.screenshot
    return `data:${screenshot.content_type}/${screenshot.format};base64,${screenshot.payload}`
  }
  return undefined
}
