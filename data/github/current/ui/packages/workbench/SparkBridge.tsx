import type React from 'react'
import {memo} from 'react'

import {UserPromptContextProvider} from './contexts/UserPromptContext'

function BridgeComponent(props: {children?: React.ReactNode}) {
  return <UserPromptContextProvider>{props.children}</UserPromptContextProvider>
}

export const SparkBridge = memo(BridgeComponent)
