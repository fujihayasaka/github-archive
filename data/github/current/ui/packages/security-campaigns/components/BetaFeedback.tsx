import {Label, Link} from '@primer/react'

export function BetaFeedback() {
  return (
    <div>
      <Label variant="success" sx={{mr: 1}}>
        Beta
      </Label>
      <Link href="https://gh.io/security-campaigns-feedback">Give feedback</Link>
    </div>
  )
}
