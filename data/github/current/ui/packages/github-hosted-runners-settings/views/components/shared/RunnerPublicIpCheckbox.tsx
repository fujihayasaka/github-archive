import {useContext, useEffect, useState} from 'react'
import {Box, Link, Checkbox, FormControl, Text, Spinner} from '@primer/react'
import {AlertFillIcon, OrganizationIcon} from '@primer/octicons-react'
import {URLS} from '../../../helpers/constants'
import {DocsContext} from '../context'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

export function RunnerPublicIpCheckbox(props: {
  checked: boolean
  onChange: (checked: boolean) => void
  isPublicIpAllowed: boolean
  runnerHasPublicIp?: boolean
  publicIpInfoPath: string
}) {
  const docsUrlBase = useContext(DocsContext)
  const networkingDocsUrl = `${docsUrlBase}${URLS.NETWORKING_DOCS}`
  const [usedIpCount, setUsedIpCount] = useState<number | null>(null)
  const [totalIpCount, setTotalIpCount] = useState<number | null>(null)
  const [disabled, setDisabled] = useState<boolean>(false)
  const [infoError, setInfoError] = useState<boolean>(false)

  useEffect(() => {
    const fetch = async () => {
      const response = await verifiedFetchJSON(props.publicIpInfoPath)
      if (response.ok) {
        const json = await response.json()
        setUsedIpCount(json['usedIpCount'])
        setTotalIpCount(json['totalIpCount'])
      } else {
        setInfoError(true)
      }
    }
    fetch()
  })

  useEffect(() => {
    // Disable the checkbox when public IP is not allowed...
    if (!props.isPublicIpAllowed) {
      setDisabled(true)
    } else if (usedIpCount === null || totalIpCount === null) {
      // ...or if we haven't figured out how many IPs are in use
      setDisabled(true)
    } else if (!props.runnerHasPublicIp && usedIpCount >= totalIpCount) {
      // ...or when all the public ips are in use (unless the runner already owns one -- need to be able to uncheck it!)
      setDisabled(true)
    } else {
      setDisabled(false)
    }
  }, [props.isPublicIpAllowed, props.runnerHasPublicIp, usedIpCount, totalIpCount])

  return (
    <FormControl disabled={disabled}>
      <Checkbox
        aria-label="Assign a unique and static public IP address range for this runner"
        checked={props.checked}
        name="isPublicIpEnabled"
        value="default"
        onChange={event => props.onChange(event.target.checked)}
        data-testid="runner-public-ip-checkbox"
      />
      <FormControl.Label sx={{pb: 1}}>
        Assign a unique &amp; static public IP address range for this runner
      </FormControl.Label>
      <FormControl.Caption>
        <Box sx={{display: 'flex', flexDirection: 'column', gap: 3}}>
          <span>
            All instances of this GitHub-hosted runner will be assigned a static IP from a range unique to this runner.{' '}
            <Link inline href={networkingDocsUrl}>
              Learn more about networking for runners.
            </Link>
          </span>
          <UsedPublicIpInfo usedIpCount={usedIpCount} totalIpCount={totalIpCount} error={infoError} />
          {!props.isPublicIpAllowed && <PublicIpDisallowed docsUrlBase={docsUrlBase} />}
        </Box>
      </FormControl.Caption>
    </FormControl>
  )
}

interface IUsedPublicIpInfoProps {
  usedIpCount: number | null
  totalIpCount: number | null
  error: boolean
}
function UsedPublicIpInfo(props: IUsedPublicIpInfoProps) {
  if (props.error) {
    return (
      <span>
        <AlertFillIcon className="mr-1" />
        There was an error getting public IP usage, please reload the page or try again later.
      </span>
    )
  }

  if (props.usedIpCount === null || props.totalIpCount === null) {
    return <Spinner size="small" data-testid="runner-public-ip-spinner" />
  }

  return (
    <span>
      You have used{' '}
      <Text sx={{fontWeight: 600, color: 'fg.default'}}>
        {props.usedIpCount} of {props.totalIpCount}
      </Text>{' '}
      available Actions Hosted Runner IP address ranges for this organization.
    </span>
  )
}

function PublicIpDisallowed(props: {docsUrlBase: string}) {
  const enterpriseDocsUrl = `${props.docsUrlBase}${URLS.ENTERPRISE_DOCS}`
  const pricingPageUrl = URLS.PRICING

  return (
    <Text sx={{color: 'fg.default', fontSize: '14px'}}>
      <OrganizationIcon /> Static IP is a GitHub Enterprise feature. Please take a look at our{' '}
      <Link inline href={pricingPageUrl}>
        pricing page
      </Link>{' '}
      to set up your Enterprise account or{' '}
      <Link inline href={enterpriseDocsUrl}>
        learn more
      </Link>
      .
    </Text>
  )
}
