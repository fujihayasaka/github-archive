import {Button} from '@primer/react'

import {InvoiceRenewalButton} from '@github-ui/licensing-common/components/InvoiceRenewalButton'
import {Product} from '@github-ui/licensing-common/types/product'
import type {InvoiceLicenseInfo} from '@github-ui/licensing-common/types/invoice-license-info'
import type {TrialInfo} from '@github-ui/licensing-common/types/trial-info'
import {CSVDownloader} from './CSVDownloader'
import type {Sku} from '../types/sku'
import type {SelfServeTrialInfo} from '../types/self-serve-trial-info'

export interface Props {
  buyButtonPath: string
  configureButtonPath: string
  eligibleForTrial: boolean
  invoiceLicenseInfo?: InvoiceLicenseInfo
  selfServeTrialInfo?: SelfServeTrialInfo
  isTeams: boolean
  teamsUsage: boolean
  isStafftools: boolean
  skus: Sku[]
  trialInfo?: TrialInfo
  onFreeTrialClick: () => void
}

export function AdvancedSecuritySummaryHeaderActions(props: Props) {
  if (props.trialInfo) {
    return (
      <>
        {props.trialInfo.isActive && <CSVDownloader skus={props.skus} />}
        {props.buyButtonPath && (
          <Button as="a" href={props.buyButtonPath} variant="default" data-testid="buy-advanced-security-button">
            Buy Advanced Security
          </Button>
        )}
      </>
    )
  }

  if (props.eligibleForTrial) {
    return (
      <Button onClick={props.onFreeTrialClick} variant="primary" data-testid="start-trial-button">
        Try free for {props.selfServeTrialInfo?.trialDays} days
      </Button>
    )
  }

  if (props.invoiceLicenseInfo) {
    return (
      <>
        <CSVDownloader skus={props.skus} />
        <InvoiceRenewalButton invoiceLicenseInfo={props.invoiceLicenseInfo} product={Product.GHAS} />
      </>
    )
  }

  if (props.isTeams) {
    if (props.teamsUsage === true) {
      return <CSVDownloader skus={props.skus} />
    }

    if (props.isStafftools || props.configureButtonPath === '') {
      return null
    }

    return (
      <Button
        as="a"
        href={props.configureButtonPath}
        variant="default"
        data-testid="advanced-security-configure-button"
      >
        Configure
      </Button>
    )
  }

  return <CSVDownloader skus={props.skus} />
}
