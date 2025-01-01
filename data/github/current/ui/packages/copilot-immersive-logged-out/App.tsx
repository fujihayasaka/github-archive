import type React from 'react'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
const App: React.FC<{children?: React.ReactNode}> = ({children}) => {
  return <>{children}</>
}

export default App
