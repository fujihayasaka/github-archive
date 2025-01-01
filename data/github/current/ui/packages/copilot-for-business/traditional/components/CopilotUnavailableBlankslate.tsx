import {Box} from '@primer/react'

export function CopilotUnavailableBlankslate() {
  return (
    <section className="Box rounded-top-0 blankslate">
      <Box sx={{alignItems: 'center', display: 'flex', flexDirection: 'column'}} data-testid="cfb-no-seats">
        <h2 className="blankslate-heading">Copilot is not available to this organization</h2>
        <p className="mb-3">
          Copilot must be enabled for this organization by your enterprise administrator before you can begin assigning
          seats.
        </p>
      </Box>
    </section>
  )
}
