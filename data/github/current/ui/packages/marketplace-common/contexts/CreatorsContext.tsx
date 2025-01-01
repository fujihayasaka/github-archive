import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'

interface CreatorsContextType {
  creators: string
  setCreators: (creators: string) => void
}

const CreatorsContext = createContext<CreatorsContextType | undefined>(undefined)

export function useCreators() {
  const context = useContext(CreatorsContext)
  if (!context) throw new Error('useCreators must be used within a CreatorsProvider')
  return context
}

export function CreatorsProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const defaultCreators = useMemo(() => {
    if (searchParams.has('verification')) {
      const verification = searchParams.get('verification')
      if (verification === 'verified_creator') {
        return 'Verified creators'
      }
    }
    return 'All creators'
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const [creators, setCreators] = useState(defaultCreators)
  const value = useMemo(() => ({creators, setCreators}), [creators, setCreators])
  return <CreatorsContext.Provider value={value}>{children}</CreatorsContext.Provider>
}
