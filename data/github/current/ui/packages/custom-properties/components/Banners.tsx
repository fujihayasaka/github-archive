import {Banner} from '@primer/react/experimental'
import {forwardRef} from 'react'

const DEFINITIONS_LIMIT = 100
export function isDefinitionsLimitReached(definitionsCount: number) {
  return definitionsCount >= DEFINITIONS_LIMIT
}
export function DefinitionsLimitBanner() {
  return (
    <Banner
      title="Definitions limit"
      hideTitle
      variant="info"
      data-testid="definitions-limit-banner"
      description={`The limit of ${DEFINITIONS_LIMIT} definitions is reached. You cannot add more.`}
    />
  )
}

export const ServerErrorFormBanner = forwardRef(ServerErrorFormBannerWithRef)

function ServerErrorFormBannerWithRef({children}: React.PropsWithChildren, ref: React.ForwardedRef<HTMLDivElement>) {
  return (
    <Banner
      title="Server error"
      hideTitle
      variant="critical"
      data-testid="server-error-banner"
      ref={ref}
      tabIndex={0}
      description={children}
    />
  )
}
interface DefinitionUsageBannerProps {
  name: string
  repoCount: number
}

export function DefinitionUsageBanner({name, repoCount}: DefinitionUsageBannerProps) {
  const hasUsages = repoCount > 0
  const reposWord = repoCount === 1 ? 'repository' : 'repositories'

  const variant = hasUsages ? 'warning' : 'info'
  const description = hasUsages ? (
    <span>
      The <strong>{name}</strong> property is referenced by{' '}
      <strong>
        {repoCount} {reposWord}.
      </strong>
    </span>
  ) : (
    <span>
      No usages of the <strong>{name}</strong> property found.
    </span>
  )

  return (
    <Banner title="Definition usage" hideTitle variant={variant} data-testid="usage-banner" description={description} />
  )
}
