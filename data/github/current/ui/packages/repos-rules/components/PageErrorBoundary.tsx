import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {IMPORT_LOCAL_STORAGE_KEY} from '../helpers/constants'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'

type PageErrorBoundaryProps = {
  children?: React.ReactNode
}

export const PageErrorBoundary = ({children}: PageErrorBoundaryProps) => {
  const [, setImportedRuleset] = useLocalStorage(IMPORT_LOCAL_STORAGE_KEY, undefined)
  return (
    <ErrorBoundary
      onError={e => {
        setImportedRuleset(undefined)
        throw e
      }}
    >
      {children}
    </ErrorBoundary>
  )
}
