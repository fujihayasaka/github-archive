import type React from 'react'
import {AlphaLabel} from '@github-ui/lifecycle-labels/alpha'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {Box, Text} from '@primer/react'
import {useAppContext} from '../../contexts/AppContext'
import SecurityConfigurationRow from './Row'
import type {OrganizationSecurityConfiguration} from '../../security-products-enablement-types'

interface SecurityConfigurationTableProps {
  tableType: string
  header: string
  managedBy?: string
}

const SecurityConfigurationTable: React.FC<SecurityConfigurationTableProps> = ({tableType, header, managedBy}) => {
  const {
    capabilities,
    githubRecommendedConfiguration,
    customSecurityConfigurations,
    customEnterpriseSecurityConfigurations,
    enterpriseConfigsAvailable,
  } = useAppContext()
  const enterprisePrivateBeta = useFeatureFlag('enterprise_security_configurations_private_beta_label')

  let configsLength = 0
  let configs = [] as OrganizationSecurityConfiguration[]

  switch (tableType) {
    case 'enterprise':
      configsLength = customEnterpriseSecurityConfigurations.length
      configs = customEnterpriseSecurityConfigurations
      break
    case 'organization':
    case 'user':
      configsLength = customSecurityConfigurations.length
      configs = customSecurityConfigurations
      break
  }

  const renderGHR = () => {
    if (!githubRecommendedConfiguration) return null

    if (
      tableType === 'enterprise' ||
      (tableType === 'organization' &&
        (!enterpriseConfigsAvailable || (enterpriseConfigsAvailable && !capabilities.enterpriseOwned))) ||
      tableType === 'user'
    ) {
      return (
        <SecurityConfigurationRow
          configuration={githubRecommendedConfiguration}
          isLast={configsLength === 0}
          configurationType={'githubRecommended'} // Mark as GitHub recommended
        />
      )
    }
    return null
  }

  return (
    <>
      <div data-hpc>
        <Box
          sx={{
            display: 'flex',
            justifyContent: 'space-between',
            backgroundColor: 'canvas.subtle',
            border: '1px solid',
            borderColor: 'border.default',
            borderRadius: '6px 6px 0 0',
            py: 2,
            px: 3,
          }}
        >
          <Text data-testid="form-title" sx={{fontWeight: 'bold', display: 'inline-flex', alignItems: 'center'}}>
            {header}
            {tableType === 'enterprise' && enterprisePrivateBeta && (
              <Box as="span" sx={{ml: 2}}>
                <AlphaLabel feedbackUrl="https://github.com/github-early-access/security-overview-private-beta-community/discussions/29" />
              </Box>
            )}
          </Text>
          <Text sx={{color: 'fg.subtle'}}>{managedBy}</Text>
        </Box>
        {renderGHR()}
        {configs.map((config, index) => (
          <SecurityConfigurationRow
            configuration={config}
            isLast={index === configsLength - 1}
            configurationType={tableType}
            key={config.id}
          />
        ))}
      </div>
    </>
  )
}

export default SecurityConfigurationTable
