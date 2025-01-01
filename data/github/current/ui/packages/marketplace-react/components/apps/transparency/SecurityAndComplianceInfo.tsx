import {TransparencyDataTable} from './TransparencyDataTable'
import {Banner} from '@primer/react/experimental'
import {Link, Text, Stack} from '@primer/react'
import {capitalize} from '../../../utilities/capitalize'
import {SafeHTMLBox} from '@github-ui/safe-html'
import type {SafeHTMLString} from '@github-ui/safe-html'

type SecurityAndComplianceInfoProps = {
  isAiHighRisk?: 'Yes' | 'No'
  llmsInUse?: string
  thirdPartyServices?: string
  repositoryVisibility?: 'public' | 'private'
  repositoryUrl?: string
  transparencyDisclosure?: string
  copilotApp: boolean
}

export function SecurityAndComplianceInfo(props: SecurityAndComplianceInfoProps) {
  const {
    isAiHighRisk,
    llmsInUse,
    thirdPartyServices,
    repositoryVisibility,
    repositoryUrl,
    transparencyDisclosure,
    copilotApp,
  } = props

  const items = [
    {
      label: 'Indemnity Status',
      value:
        copilotApp &&
        "Not covered by Microsoft's indemnity policy. All other Copilot features retain indemnity coverage.",
    },
    {
      label: 'Classified as high risk by EU AI Act',
      value: isAiHighRisk && <>{isAiHighRisk}</>,
    },
    {
      label: 'Models used',
      value: llmsInUse && <>{llmsInUse}</>,
    },
    {
      label: 'Third party services used',
      value: thirdPartyServices && <>{thirdPartyServices}</>,
    },
    {
      label: 'Repository visibility',
      value: repositoryVisibility && <>{capitalize(repositoryVisibility)}</>,
    },
    {
      label: 'Repository URL',
      value: repositoryUrl && <Link href={repositoryUrl}>{repositoryUrl}</Link>,
    },
    {
      label: 'Disclosures',
      value: transparencyDisclosure && (
        <SafeHTMLBox className="text-small markdown-body my-1" html={transparencyDisclosure as SafeHTMLString} />
      ),
    },
  ]

  return (
    <Stack gap="normal" data-testid="security-compliance-info">
      <TransparencyDataTable items={items} />
      <Banner
        title="Info"
        hideTitle
        description={
          <>
            <Text weight="semibold">Note:</Text> Security & Compliance information is self-attested by the publisher.
            Only the Publisher and Permissions information is verified by GitHub. Make sure to conduct your own security
            reviews.
          </>
        }
      />
    </Stack>
  )
}
