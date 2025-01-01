import {Text} from '@primer/react'
import React from 'react'

export interface LicenseCountPart {
  count: number
  suffix: string
}

export interface ServerLicensesInfo {
  prefix: string
  count?: number
  suffix?: string
  parts?: LicenseCountPart[]
}

export interface ServerLicensesFooterProps {
  licensesInfo?: ServerLicensesInfo
}

function renderLicenseParts(parts: LicenseCountPart[]) {
  return parts.map((part, index) => (
    <React.Fragment key={part.suffix}>
      <Text as="span" weight="semibold">
        {part.count}
      </Text>
      {part.suffix}
      {index < parts.length - 1 && <span>, </span>}
    </React.Fragment>
  ))
}

export function ServerLicensesFooter({licensesInfo}: ServerLicensesFooterProps) {
  if (!licensesInfo) return null

  const {prefix, parts, count, suffix} = licensesInfo

  return (
    <div className="Box-footer px-4 f6" data-testid="server-licenses-footer">
      <Text className="color-fg-muted" size="medium" data-testid="server-licenses-text">
        {prefix}
        {parts && parts.length > 0 ? (
          <>{renderLicenseParts(parts)}</>
        ) : (
          <>
            <Text as="span" size="medium" weight="semibold">
              {count}
            </Text>
            {suffix}
          </>
        )}
      </Text>
    </div>
  )
}
