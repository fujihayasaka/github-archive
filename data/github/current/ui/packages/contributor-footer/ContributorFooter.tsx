import {InfoIcon} from '@primer/octicons-react'
import {Box, Link, type BetterSystemStyleObject} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {Fragment} from 'react'
import {isEnterprise} from '@github-ui/runtime-environment'

export type ContributorFooterProps = {
  contributingFileUrl?: string
  securityPolicyUrl?: string
  codeOfConductFileUrl?: string
  sx?: BetterSystemStyleObject
}

export function ContributorFooter({
  contributingFileUrl,
  securityPolicyUrl,
  codeOfConductFileUrl,
  sx,
}: ContributorFooterProps) {
  if (isEnterprise() || (!contributingFileUrl && !securityPolicyUrl && !codeOfConductFileUrl)) return null

  const Links = () => {
    const existingLinks = []

    if (contributingFileUrl) {
      existingLinks.push(
        <Link underline href={contributingFileUrl}>
          contributing guidelines
        </Link>,
      )
    }

    if (securityPolicyUrl) {
      existingLinks.push(
        <Link underline href={securityPolicyUrl}>
          security policy
        </Link>,
      )
    }

    if (codeOfConductFileUrl) {
      existingLinks.push(
        <Link underline href={codeOfConductFileUrl}>
          code of conduct
        </Link>,
      )
    }

    if (existingLinks.length === 1) return <>{existingLinks.pop()}</>

    const lastLink = existingLinks.pop()
    return (
      <>
        {existingLinks.map((link, i) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <Fragment key={i}>
            {link}
            <span>{i !== existingLinks.length - 1 ? ', ' : ' '}</span>
          </Fragment>
        ))}
        <span>and {lastLink}</span>
      </>
    )
  }

  return (
    <Box
      data-testid="contributor-footer"
      sx={{display: 'flex', alignItems: 'flex-start', gap: 1, pt: 2, color: 'fg.muted', fontSize: 0, ...sx}}
    >
      <Octicon icon={InfoIcon} sx={{mt: '1px'}} />
      <div data-testid="contributor-footer-text">
        {/*
          🚨 Heads up! These spans are like a house of cards - touch them and
          built-in browser translation will wreak havoc on the DOM and react will crash.
          Proceed with extreme caution! 🏗️
        */}
        <span>Remember, contributions to this repository should follow its </span>
        <span>
          <Links />
        </span>
        <span>.</span>
      </div>
    </Box>
  )
}
