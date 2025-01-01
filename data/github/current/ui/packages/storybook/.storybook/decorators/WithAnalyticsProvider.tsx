import {AnalyticsProvider} from "@github-ui/analytics-provider"
import type {Decorator} from "@storybook/react"

const metadata = {}

export const withAnalyticsProvider: Decorator = (
  Story,
  context
) => {
  return (
    <AnalyticsProvider appName="storybook-app" category="" metadata={metadata}>
      {Story(context)}
    </AnalyticsProvider>
  )
}
