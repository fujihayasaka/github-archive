import {AnalyticsContext} from '@github-ui/analytics-provider/context'
import type {ErrorContext} from '@github-ui/failbot'
// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import React from 'react'

import {ErrorPage} from './ErrorPage'

// NOTE(jon, 2022-02-28): I copied 99% of this from memex's error-boundary

export interface ErrorBoundaryProps {
  children: React.ReactNode
  fallback?: React.ReactNode
  /**
   * Provide a callback to be invoked when an error is thrown (can be used for logging errors)
   */
  onError?: (error: Error, context?: ErrorContext) => void
  critical?: boolean
  appName?: string
}

interface ErrorBoundaryState {
  error: Error | null
}

class BasicErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props)

    this.state = {
      error: null,
    }
  }

  /**
   * Invoked when an error is thrown in the child component,
   * and used to update state in a concurrent friendly manner
   */
  static getDerivedStateFromError(error: Error) {
    return {error}
  }

  /**
   * Called _after_ the re-render, used for performing side-effects such as logging
   */
  override componentDidCatch(error: Error) {
    const context = {
      critical: this.props.critical || false,
      reactAppName: this.props.appName,
    }

    if (typeof this.props.onError === 'function') {
      this.props.onError(error, context)
    } else {
      defaultOnError(error, context)
    }
  }

  override render() {
    if (!this.state.error) return this.props.children

    return this.props.fallback === undefined ? <ErrorPage type="httpError" /> : this.props.fallback
  }
}

export function ErrorBoundary(props: ErrorBoundaryProps) {
  const context = React.useContext(AnalyticsContext)
  const appName = props.appName || context?.appName
  return <BasicErrorBoundary {...props} appName={appName} />
}

function defaultOnError(error: Error, context: ErrorContext = {}) {
  setTimeout(() => {
    reportError(error, context)
  })
}
