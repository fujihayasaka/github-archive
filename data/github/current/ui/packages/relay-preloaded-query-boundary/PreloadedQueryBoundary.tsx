import type {ReactNode} from 'react'
import {Component, useContext} from 'react'
// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import {AnalyticsContext} from '@github-ui/analytics-provider/context'

export type PreloadedQueryBoundaryProps = {
  children: ReactNode
  onRetry: () => void
  fallback?: (retry: () => void, error: Error) => ReactNode
  critical?: boolean
  appName?: string
}

type State = {
  error: Error | null
}

const defaultFallBack = (retry: () => void) => {
  return (
    <div>
      <span>Error:</span>
      <button onClick={retry}>Retry</button>
    </div>
  )
}

export type ReportableError = Error & {shouldSkipReport?: boolean}

export class BasicPreloadedQueryBoundary extends Component<PreloadedQueryBoundaryProps, State> {
  override state = {error: null}

  static getDerivedStateFromError(error: Error): State {
    return {error}
  }

  override componentDidCatch(error: ReportableError) {
    const shouldSkipReport = error.shouldSkipReport ?? false

    const context = {
      critical: this.props.critical || false,
      reactAppName: this.props.appName,
    }

    // Not report it to Sentry if ES is down
    if (shouldSkipReport) return

    // Log errors directly instead of using the global window error callback
    // to avoid hitting the global error boundary.
    reportError(error, context)
  }

  _retry = () => {
    // This ends up calling loadQuery again to get and render
    // a new query reference
    this.props.onRetry()
    this.setState({
      // Clear the error
      error: null,
    })
  }

  override render() {
    const {children} = this.props
    const {error} = this.state
    const fallback = this.props.fallback || defaultFallBack

    if (error) {
      return fallback(this._retry, error)
    }

    return children
  }
}

export default function PreloadedQueryBoundary(props: PreloadedQueryBoundaryProps) {
  const context = useContext(AnalyticsContext)
  const appName = props.appName || context?.appName
  return <BasicPreloadedQueryBoundary {...props} appName={appName} />
}
