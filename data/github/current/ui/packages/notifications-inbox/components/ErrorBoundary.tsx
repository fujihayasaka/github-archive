import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import type {ErrorBoundaryProps} from '@github-ui/react-core/error-boundary'

import {LABELS} from './../notifications/constants/labels'
import {Error} from './ListError'

const defaultFallback = <Error title={LABELS.failedToLoadInbox} message={LABELS.errorLoading} />
function NotificationsErrorBoundary({fallback = defaultFallback, ...props}: ErrorBoundaryProps) {
  return <ErrorBoundary {...props} fallback={fallback} />
}

export default NotificationsErrorBoundary
