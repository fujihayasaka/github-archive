import type {PathFunction} from '@github-ui/paths'

export const dismissNoticePath: PathFunction<{notice: string}> = ({notice}) => `/settings/dismiss-notice/${notice}`

export const dismissFailureBannerPath: PathFunction<{org: string}> = ({org}) =>
  `/organizations/${org}/settings/security_products/dismiss_failure_banner`
