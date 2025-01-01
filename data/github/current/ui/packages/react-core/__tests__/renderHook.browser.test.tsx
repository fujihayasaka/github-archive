// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {describe, expect, it} from '@github-ui/tests'
import {useQueryClient} from '@tanstack/react-query'
import {createContext, type PropsWithChildren, useContext} from 'react'

import {renderHook} from '../test-utils/Render'

const TestContext = createContext<string | undefined>(undefined)

function TestProvider({
  value,
  children,
}: PropsWithChildren<{
  value: string
}>) {
  return <TestContext.Provider value={value}>{children}</TestContext.Provider>
}

function useTestHook() {
  const context = useContext(TestContext)
  if (!context) {
    throw new Error('useTestHook must be used within a TestProvider')
  }
  return context
}

describe('supports using a custom wrapper', () => {
  it('renders correctly with a custom wrapper', () => {
    const wrapper = ({children}: {children: React.ReactNode}) => (
      <TestProvider value="test-value">{children}</TestProvider>
    )
    const {result} = renderHook(() => useTestHook(), {wrapper})
    expect(result.current).toBe('test-value')
  })

  it('has access to default providers like QueryClientProvider', () => {
    const {result} = renderHook(() => useQueryClient())
    expect(result).toBeDefined()
  })
})
