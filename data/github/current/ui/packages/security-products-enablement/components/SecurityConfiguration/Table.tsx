import type React from 'react'
import {useAppContext} from '../../contexts/AppContext'
import SecurityConfigurationRow from './Row'
import type {MiniSecurityConfiguration} from '../../security-products-enablement-types'

import styles from './Table.module.css'

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

  let configsLength = 0
  let configs = [] as MiniSecurityConfiguration[]

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
        <div className={styles.Box}>
          <span data-testid="form-title" className={styles.Text}>
            {header}
          </span>
          <span className={styles.Text_1}>{managedBy}</span>
        </div>
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
