import {ProgressBar} from '@primer/react'
import {DotFillIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import styles from './EnterpriseCloudSeatCount.module.css'

export interface Props {
  canViewMembers: boolean
  isTrial: boolean
  isVolumeLicensed: boolean
  enterpriseLicensesConsumed: number
  enterpriseLicensesPurchased: number
  vssLicensesConsumed: number
  vssLicensesPurchasedWithOverage: number
}
export function EnterpriseCloudSeatCount({
  isTrial,
  isVolumeLicensed,
  enterpriseLicensesConsumed,
  enterpriseLicensesPurchased,
  vssLicensesConsumed,
  vssLicensesPurchasedWithOverage,
}: Props) {
  return !isVolumeLicensed && !isTrial ? (
    <SeatCountNoLimit seatsUsed={enterpriseLicensesConsumed} />
  ) : (
    <SeatCountLimited
      enterpriseLicensesConsumed={enterpriseLicensesConsumed}
      totalAvailableLicenses={enterpriseLicensesPurchased + vssLicensesPurchasedWithOverage}
      vssLicensesConsumed={vssLicensesConsumed}
      vssLicensesPurchased={vssLicensesPurchasedWithOverage}
    />
  )
}

function SeatCountLimited({
  enterpriseLicensesConsumed,
  totalAvailableLicenses,
  vssLicensesConsumed,
  vssLicensesPurchased,
}: {
  enterpriseLicensesConsumed: number
  totalAvailableLicenses: number
  vssLicensesConsumed: number
  vssLicensesPurchased: number
}) {
  const totalConsumed = enterpriseLicensesConsumed + vssLicensesConsumed
  const enterpriseProgress =
    totalAvailableLicenses !== 0 ? (enterpriseLicensesConsumed / totalAvailableLicenses) * 100 : 100
  const vssProgress = totalAvailableLicenses !== 0 ? (vssLicensesConsumed / totalAvailableLicenses) * 100 : 100
  const showVss = vssLicensesPurchased > 0

  const ariaBreakdownTextEnterprise = `${enterpriseLicensesConsumed.toLocaleString()} Enterprise licenses used.`
  const ariaBreakdownTextVss = showVss ? `${vssLicensesConsumed.toLocaleString()} Visual Studio licenses used.` : ''

  return (
    <div className="mb-1 d-flex flex-column gap-2 width-full">
      <div className="d-flex flex-justify-between flex-items-baseline flex-wrap">
        <div className={clsx('f3', styles.lineHeightSpacious)} data-testid="seat-count-total-consumed">
          {totalConsumed.toLocaleString()}
        </div>
        <div className="color-fg-muted no-wrap" data-testid="seat-count-total-purchased">
          {totalAvailableLicenses.toLocaleString()} available
        </div>
      </div>
      <div>
        <ProgressBar
          barSize="small"
          aria-label="Consumed seats"
          data-testid="seat-count-progress-bar"
          aria-valuetext={`${ariaBreakdownTextEnterprise} ${ariaBreakdownTextVss}`}
        >
          <ProgressBar.Item
            key="enterprise"
            progress={enterpriseProgress}
            aria-label="Enterprise licenses used"
            aria-valuetext={ariaBreakdownTextEnterprise}
            className={clsx(styles.enterpriseProgressBar)}
            data-testid="seat-count-progress-enterprise"
            role="progressbar"
          />
          {showVss && (
            <ProgressBar.Item
              key="vss"
              progress={vssProgress}
              aria-label="Visual Studio licenses used"
              aria-valuetext={ariaBreakdownTextVss}
              className={clsx(styles.vssProgressBar)}
              data-testid="seat-count-progress-vss"
              role="progressbar"
            />
          )}
        </ProgressBar>
        {showVss && (
          <div className="d-flex flex-row mt-2 f6" data-testid="seat-count-legend">
            <div className="d-flex flex-row flex-items-center mr-3">
              <DotFillIcon size={16} className="mr-1 fgColor-accent-emphasis" />
              <span className="mr-1 text-bold">Enterprise</span>
              <span data-testid="seat-count-legend-enterprise-count">
                {enterpriseLicensesConsumed.toLocaleString()}
              </span>
            </div>
            <div className="d-flex flex-row flex-items-center">
              <DotFillIcon size={16} className="mr-1 fgColor-success" />
              <span className="mr-1 text-bold">Visual Studio</span>
              <span data-testid="seat-count-legend-vss-count">{vssLicensesConsumed.toLocaleString()}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function SeatCountNoLimit({seatsUsed}: {seatsUsed: number}) {
  return (
    <div className={clsx('f3', styles.lineHeightSpacious)} data-testid="seat-count-used-no-limit">
      {seatsUsed.toLocaleString()}
    </div>
  )
}
