import {Text} from '@primer/react'
import type {ReactNode} from 'react'

export const WithAnimatedEllipsis = ({children}: {children: ReactNode}) => {
  const animations = `
    @keyframes dot1 {
      0%, 75% { opacity: 1; }
      100% { opacity: 0; }
    }
    @keyframes dot2 {
      0% { opacity: 0; }
      15% { opacity: 0; }
      25%, 75% { opacity: 1; }
      100% { opacity: 0; }
    }
    @keyframes dot3 {
      0% { opacity: 0; }
      40% { opacity: 0; }
      50%, 75% { opacity: 1; }
      100% { opacity: 0; }
    }
  `

  return (
    <>
      {children}
      <style>{animations}</style>
      {[1, 2, 3].map(dotNumber => (
        <Text key={`dot${dotNumber}`} sx={{opacity: 0, animation: '2s infinite', animationName: `dot${dotNumber}`}}>
          .
        </Text>
      ))}
    </>
  )
}
