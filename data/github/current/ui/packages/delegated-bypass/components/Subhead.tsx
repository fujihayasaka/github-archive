import type {FC} from 'react'
import {Box, Heading, Text, Label} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type SubheadProps = {
  heading: string
  description?: string
  className?: string
  beta?: boolean
  renderAction?: () => JSX.Element | null
}

export const Subhead: FC<SubheadProps> = ({heading, description, className, beta, renderAction}) => {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')

  return (
    <Box
      sx={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}
      className={`Subhead ${className || ''}`}
    >
      <Box sx={{display: 'flex', alignItems: 'center', gap: 2}}>
        <Heading as="h1" sx={{fontSize: 24, fontWeight: 'light'}} className="Subhead-heading">
          {heading}
        </Heading>
        {beta ? (
          lifecycleLabelNameEnabled ? (
            <div className="ml-2">
              <BetaLabel />
            </div>
          ) : (
            <Label sx={{ml: 2}} variant="success">
              Beta
            </Label>
          )
        ) : null}
        {description ? (
          <Text sx={{mb: 2}} className="Subhead-description">
            {description}
          </Text>
        ) : null}
      </Box>

      {renderAction?.()}
    </Box>
  )
}
