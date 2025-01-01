import {Box, Link} from '@primer/react'
import type {AppListing} from '@github-ui/marketplace-common'

export const CopilotListingRequirement = (_props: {listing: AppListing}) => {
  return (
    <>
      <h3 className="mb-4 mt-4">Requirements</h3>
      <Box
        className="mb-4 mt-4"
        sx={{
          width: '100%',
          borderColor: 'border.default',
          borderStyle: 'solid',
          borderWidth: 1,
          borderRadius: 2,
          display: 'flex',
          flexDirection: 'column',
          boxShadow: 'var(--shadow-resting-small,var(--color-shadow-small))',
        }}
      >
        <p className="p-3" data-testid="copilot-listing-requirement">
          Using Copilot Extensions requires and{' '}
          <LinkText href="https://github.com/features/copilot/plans" text="GitHub Copilot License" />. Copilot
          extensions are currently in{' '}
          <LinkText href="https://github.com/orgs/community/discussions/137975" text="limited public beta" /> and by
          intalling, you agree to{' '}
          <LinkText
            href="https://docs.github.com/en/site-policy/github-terms/github-pre-release-license-terms"
            text="pre-release terms"
          />
          .
        </p>
      </Box>
    </>
  )
}

const LinkText = ({href, text}: {href: string; text: string}) => {
  return (
    <Link inline href={href}>
      {text}
    </Link>
  )
}
