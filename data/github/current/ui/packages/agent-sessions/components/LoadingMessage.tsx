import {CopilotAnimation, CopilotAnimationType} from '@github-ui/copilot-animation'
import {WithShimmerEffect} from '@github-ui/copilot-chat/components/WithShimmerEffect'
import {Stack} from '@primer/react'
import {useState, useRef, useEffect} from 'react'

const predefinedMessages = [
  'Spinning up dev environment…',
  'Starting MCP servers…',
  'Making sure Copilot feels comfortable in the cockpit…',
  'Fueling the runtime engines…',
  'Clearing the airspace for MCP traffic…',
  'Cabin pressure stable. Almost ready…',
  'Reticulating goggles...',
  'Calibrating flux capacitor...',
  'Copilot adjusting seatbelt…',
  'Waiting for clearance from GitHub tower…',
  'Final systems check, standing by…',
  'Takeoff soon™…',
]

export function BootingUpMessage() {
  const [loadingMessageIndex, setLoadingMessageIndex] = useState(0)
  const intervalRef = useRef<NodeJS.Timeout | null>(null)

  useEffect(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current)
      intervalRef.current = null
    } else {
      intervalRef.current = setInterval(() => {
        setLoadingMessageIndex(prev => {
          if (prev < predefinedMessages.length - 1) {
            return prev + 1
          }
          return prev // stay on last message
        })
      }, 7000)
    }

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current)
        intervalRef.current = null
      }
    }
  }, [])
  // We should never hit the fallback case, but typescript complains if we don't handle it
  return <LoadingMessage message={predefinedMessages[loadingMessageIndex] || 'Loading…'} />
}

export function LoadingMessage({message}: {message: string}) {
  return (
    <Stack direction="horizontal" padding="none" align="center" justify="start" gap="condensed">
      <CopilotAnimation animationType={CopilotAnimationType.Thinking} loopAnimation />
      <WithShimmerEffect className="color-fg-muted">{message}</WithShimmerEffect>
    </Stack>
  )
}
