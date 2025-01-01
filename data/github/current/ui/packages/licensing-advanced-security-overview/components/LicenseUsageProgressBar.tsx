import {ProgressBar} from '@primer/react'

export interface LicenseUsageProgressBarProps {
  consumedLicenses: number
  purchasedLicenses: number
}

export function LicenseUsageProgressBar({consumedLicenses, purchasedLicenses}: LicenseUsageProgressBarProps) {
  const ariaLabelValue = `${consumedLicenses.toLocaleString()} licenses used.`
  const progress = purchasedLicenses !== 0 ? (consumedLicenses / purchasedLicenses) * 100 : 100
  return (
    <ProgressBar
      barSize="small"
      aria-label="Consumed seats"
      data-testid="seat-count-progress-bar"
      aria-valuetext={`${ariaLabelValue}`}
    >
      <ProgressBar.Item
        progress={progress}
        aria-label="Licenses used"
        aria-valuetext={ariaLabelValue}
        className="bgColor-accent-emphasis"
        data-testid="license-usage-progress"
        role="progressbar"
      />
    </ProgressBar>
  )
}
