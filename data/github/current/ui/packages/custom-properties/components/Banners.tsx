import {AlertIcon, InfoIcon} from '@primer/octicons-react'
import {Box, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {forwardRef} from 'react'

const DEFINITIONS_LIMIT = 100
export function isDefinitionsLimitReached(definitionsCount: number) {
  return definitionsCount >= DEFINITIONS_LIMIT
}
export function DefinitionsLimitBanner() {
  return (
    <Flash>
      <Box sx={{display: 'flex', gap: 1}}>
        <div>
          <Octicon icon={InfoIcon} />
        </div>
        <div>The limit of {DEFINITIONS_LIMIT} definitions is reached. You cannot add more.</div>
      </Box>
    </Flash>
  )
}

export const ServerErrorFormBanner = forwardRef(ServerErrorFormBannerWithRef)

function ServerErrorFormBannerWithRef({children}: React.PropsWithChildren, ref: React.ForwardedRef<HTMLDivElement>) {
  return (
    <Flash data-testid="server-error-banner" variant="danger" ref={ref} tabIndex={0}>
      <Box sx={{display: 'flex', gap: 1}}>
        <div>
          <Octicon icon={AlertIcon} />
        </div>
        <div>{children}</div>
      </Box>
    </Flash>
  )
}
interface DefinitionUsageBannerProps {
  name: string
  repoCount: number
}

export function DefinitionUsageBanner({name, repoCount}: DefinitionUsageBannerProps) {
  if (repoCount) {
    const reposWord = repoCount === 1 ? 'repository' : 'repositories'
    return (
      <Flash sx={{p: 2}} variant="warning" data-testid="usage-banner">
        <span>
          The <strong>{name}</strong> property is referenced by{' '}
          <strong>
            {repoCount} {reposWord}.
          </strong>
        </span>
      </Flash>
    )
  }

  return (
    <Flash sx={{p: 2}} variant="default" data-testid="usage-banner">
      <span>
        No usages of the <strong>{name}</strong> property found.
      </span>
    </Flash>
  )
}
