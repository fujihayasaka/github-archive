import {Heading, Text, Link, Stack} from '@primer/react'
import {Revealer} from './Revealer'
import {PublisherInfo} from './transparency/PublisherInfo'
import {PermissionsInfo} from './transparency/PermissionsInfo'
import {ScopesInfo} from './transparency/ScopesInfo'
import {SecurityAndComplianceInfo} from './transparency/SecurityAndComplianceInfo'
import {ExportButton} from './transparency/ExportButton'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {AppListing} from '@github-ui/marketplace-common'
import type {PermissionsData} from '../../types'

export type TransparencySectionProps = {
  app: AppListing
  permissionsData: PermissionsData[]
}

export function TransparencySection({app, permissionsData}: TransparencySectionProps) {
  const {
    isAiHighRisk,
    llmsInUse,
    thirdPartyServices,
    repositoryVisibility,
    repositoryUrl,
    transparencyDisclosure,
    copilotApp,
  } = app
  const securityAndComplianceFields = {
    isAiHighRisk,
    llmsInUse,
    thirdPartyServices,
    repositoryVisibility,
    repositoryUrl,
    transparencyDisclosure,
    copilotApp,
  }
  const shouldRenderSecurityAndCompliance = Object.values(securityAndComplianceFields).some(value => value)
  const shouldAllowCsvExports = useFeatureFlag('marketplace_transparency_exports')

  const infoSections = [
    {
      title: '1. Publisher',
      content: <PublisherInfo app={app} />,
      defaultOpen: true,
    },
    {
      title: '2. Permissions',
      content:
        app.listableType === 'Integration' ? <PermissionsInfo permissionsData={permissionsData} /> : <ScopesInfo />,
      defaultOpen: false,
    },
    {
      title: '3. Security & Compliance',
      content: shouldRenderSecurityAndCompliance && <SecurityAndComplianceInfo {...securityAndComplianceFields} />,
      defaultOpen: false,
    },
  ]

  return (
    <div data-testid="transparency-section">
      <Stack
        className="pb-3"
        gap="condensed"
        direction={{narrow: 'vertical', regular: 'horizontal'}}
        align={{narrow: 'start', regular: 'center'}}
        justify="space-between"
      >
        <Heading as="h2" variant="medium">
          Transparency and security
        </Heading>
        {shouldAllowCsvExports && <ExportButton app={app} />}
      </Stack>
      {infoSections.map(
        section =>
          section.content && (
            <Revealer key={section.title} title={section.title} defaultOpen={section.defaultOpen}>
              {section.content}
            </Revealer>
          ),
      )}
      <div className="border-top color-border-muted pt-3">
        <Text size="small" className="fgColor-muted">
          For more information on the terms of service on the GitHub Marketplace, please visit the{' '}
          <Link
            inline
            href="https://docs.github.com/en/site-policy/github-terms/github-marketplace-developer-agreement"
          >
            Marketplace Developer Agreement
          </Link>
          .
        </Text>
      </div>
    </div>
  )
}
