import React from 'react'

import {ErrorFallback} from './ErrorFallback'

export interface ComponentErrorBoundaryProps {
  children: React.ReactNode
  name: string
  fallback?: React.ReactNode
  onError?: (error: Error) => void
}

interface ComponentErrorBoundaryState {
  error: Error | null
}

export class ComponentErrorBoundary extends React.Component<ComponentErrorBoundaryProps, ComponentErrorBoundaryState> {
  constructor(props: ComponentErrorBoundaryProps) {
    super(props)

    this.state = {
      error: null,
    }
  }

  static getDerivedStateFromError(error: Error) {
    return {error}
  }

  override componentDidCatch(error: Error) {
    if (typeof this.props.onError === 'function') {
      this.props.onError(error)
    }
  }

  private getRegionName = (name: string) => {
    switch (name) {
      case 'canvas':
        return 'The canvas'
      case 'side-panel':
        return 'The side panel'
      default:
        return 'This component'
    }
  }

  override render() {
    if (!this.state.error) {
      return this.props.children
    }

    if (this.props.fallback !== undefined) {
      return this.props.fallback
    }

    return <ErrorFallback regionName={this.getRegionName(this.props.name)} />
  }
}
