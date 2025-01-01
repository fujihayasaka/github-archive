// components
import {Button, Dialog, IconButton, AnchoredOverlay, Stack, Text, Link} from '@primer/react'
import {ServerIcon, InfoIcon} from '@primer/octicons-react'

// styles/utils
import {format} from 'date-fns'
import {clsx} from 'clsx'
import styles from './EnterpriseServerSummary.module.css'

import {SummaryCard} from '@github-ui/licensing-common/components/SummaryCard'

// hooks/contexts
import {useState} from 'react'

export interface EnterpriseServerSummaryProps {
  dueDate: Date
  hasEnterpriseServer: boolean
  ghesLicenseCount: number
  ghesBillableLicenseCount: number
  bundledGhasLicenseCount: number
  bundledGhasBillableLicenseCount: number
  codeSecurityLicenseCount: number
  codeSecurityBillableLicenseCount: number
  secretProtectionLicenseCount: number
  secretProtectionBillableLicenseCount: number
  ghesUnitPrice: number
  bundledGhasUnitPrice: number
  codeSecurityUnitPrice: number
  secretProtectionUnitPrice: number
}
export function EnterpriseServerSummary(props: EnterpriseServerSummaryProps) {
  const [isInfoOpen, setIsInfoOpen] = useState<boolean>(false)
  const [isOpen, setIsOpen] = useState<boolean>(false)
  const billingDetailsHref = './billing/usage'

  const billableLicenseCount = (
    props.ghesBillableLicenseCount +
    props.bundledGhasBillableLicenseCount +
    props.codeSecurityBillableLicenseCount +
    props.secretProtectionBillableLicenseCount
  ).toLocaleString()

  const dollarAmount = (amount: number) => {
    return amount.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2})
  }

  const dollarAmountHideZeroCents = (amount: number) => {
    if (amount % 1 !== 0) {
      return dollarAmount(amount)
    } else {
      return amount.toLocaleString('en-US', {minimumFractionDigits: 0, maximumFractionDigits: 0})
    }
  }

  const totalBill = dollarAmount(
    props.ghesBillableLicenseCount * props.ghesUnitPrice +
      props.bundledGhasBillableLicenseCount * props.bundledGhasUnitPrice +
      props.codeSecurityBillableLicenseCount * props.codeSecurityUnitPrice +
      props.secretProtectionBillableLicenseCount * props.secretProtectionUnitPrice,
  )
  const ghesBill = dollarAmount(props.ghesUnitPrice * props.ghesBillableLicenseCount)
  const ghasBill = dollarAmount(props.bundledGhasUnitPrice * props.bundledGhasBillableLicenseCount)
  const codeSecurityBill = dollarAmount(props.codeSecurityUnitPrice * props.codeSecurityBillableLicenseCount)
  const secretProtectionBill = dollarAmount(
    props.secretProtectionUnitPrice * props.secretProtectionBillableLicenseCount,
  )

  let ghasComponent

  if (props.bundledGhasLicenseCount > 0) {
    ghasComponent = (
      <Stack.Item grow>
        <div className={clsx('f3', styles.lineHeightSpacious)} data-testid="seat-count-used-no-limit">
          {props.bundledGhasLicenseCount.toLocaleString()}
        </div>
        <div className="text-small color-fg-muted pt-2" data-testid="seat-count-description">
          Advanced Security
        </div>
      </Stack.Item>
    )
  } else if (props.codeSecurityLicenseCount > 0 || props.secretProtectionLicenseCount > 0) {
    ghasComponent = (
      <>
        <Stack.Item grow>
          <div className={clsx('f3', styles.lineHeightSpacious)} data-testid="seat-count-used-no-limit">
            {props.codeSecurityLicenseCount.toLocaleString()}
          </div>
          <div className="text-small color-fg-muted pt-2" data-testid="seat-count-description">
            Code Security
          </div>
        </Stack.Item>
        <Stack.Item grow>
          <div className={clsx('f3', styles.lineHeightSpacious)} data-testid="seat-count-used-no-limit">
            {props.secretProtectionLicenseCount.toLocaleString()}
          </div>
          <div className="text-small color-fg-muted pt-2" data-testid="seat-count-description">
            Secret Protection
          </div>
        </Stack.Item>
      </>
    )
  }

  let component
  if (!props.hasEnterpriseServer) {
    component = (
      <div className="Box-footer d-flex flex-items-center flex-justify-between border-0 pb-0">
        <div className="text-normal ml-1 pl-6 color-fg-default">
          You don&apos;t have any server licenses or instances. Download a new license in the Enterprise Server license
          keys section.
        </div>
      </div>
    )
  } else if (props.ghesLicenseCount === 0) {
    component = (
      <div className="Box-footer d-flex flex-items-center flex-justify-between border-0 pb-0">
        <div className="text-normal ml-1 pl-6 color-fg-default">
          All your server users are matched with your cloud users! See Enterprise Cloud to view your license usage.
        </div>
      </div>
    )
  } else {
    component = (
      <div className={clsx('pt-3', 'px-4', 'pb-2')}>
        <Stack direction="horizontal">
          <Stack.Item className={clsx(styles.evenFlexBasis)}>
            <Stack direction="vertical" grow gap="none">
              <Stack direction="horizontal" gap="condensed">
                <h4 className={clsx(styles.subHeaderPadding, 'f5')}>Consumed licenses</h4>
                <AnchoredOverlay
                  open={isInfoOpen}
                  width="medium"
                  onOpen={() => setIsInfoOpen(true)}
                  onClose={() => setIsInfoOpen(false)}
                  overlayProps={{
                    role: 'dialog',
                    'aria-modal': true,
                    sx: {
                      minWidth: '300px',
                    },
                  }}
                  side="outside-top"
                  anchorId="consumed-licenses-info-icon"
                  align="center"
                  aria-label="About consumed licenses"
                  focusZoneSettings={{
                    disabled: true,
                  }}
                  preventOverflow={false}
                  renderAnchor={innerProps => {
                    const {'aria-labelledby': ignored, 'aria-describedby': ignored2, ...rest} = innerProps
                    return (
                      <IconButton {...rest} aria-label="About consumed licenses" variant="invisible" icon={InfoIcon} />
                    )
                  }}
                >
                  <Stack direction="vertical" gap="normal" justify="center" padding="spacious">
                    <Text className="p0" size="medium" weight="semibold">
                      Consumed licenses
                    </Text>
                    <Text className="color-fg-muted p0" size="medium">
                      Non-cloud consumed licenses on Enterprise Server.
                    </Text>
                    <Link
                      href="https://docs.github.com/en/enterprise-cloud@latest/billing/using-the-new-billing-platform/about-usage-based-billing-for-licenses"
                      data-testid="seat-count-learn-more-link"
                    >
                      Learn more
                    </Link>
                  </Stack>
                </AnchoredOverlay>
              </Stack>
              <Stack direction="horizontal">
                <Stack.Item grow>
                  <div className={clsx('f3', styles.lineHeightSpacious)} data-testid="seat-count-used-no-limit">
                    {props.ghesLicenseCount.toLocaleString()}
                  </div>
                  <div className="text-small color-fg-muted pt-2" data-testid="seat-count-description">
                    Enterprise licenses
                  </div>
                </Stack.Item>
                {ghasComponent}
              </Stack>
            </Stack>
          </Stack.Item>
          <Stack.Item className={clsx('pl-4', styles.leftBorder, styles.evenFlexBasis)}>
            <Stack direction="vertical" gap="none">
              <Stack direction="horizontal" gap="condensed">
                <Stack.Item grow>
                  <h4 className={clsx(styles.subHeaderPadding, 'f5')}>Estimated next payment</h4>
                </Stack.Item>
                <Stack.Item>
                  <Button
                    size="small"
                    className="mt-1"
                    data-testid="details"
                    variant="invisible"
                    onClick={() => setIsOpen(!isOpen)}
                  >
                    More details
                  </Button>
                  {isOpen && (
                    <Dialog width="large" title="Estimated next payment" onClose={() => setIsOpen(false)}>
                      <div className={clsx('f3', styles.lineHeightSpacious)}>${totalBill}</div>
                      <div className="color-fg-muted mt-2">
                        Amount based on {billableLicenseCount} billable non-cloud licenses on Enterprise Server, due by{' '}
                        {format(props.dueDate, 'MMMM d, yyyy')}.
                      </div>
                      <hr className="my-2" />
                      <div className="d-flex flex-row gap-1">
                        <div className="d-flex flex-column flex-1">
                          <div>{props.ghesBillableLicenseCount.toLocaleString()} Enterprise licenses</div>
                          <div className="color-fg-muted">
                            ${dollarAmountHideZeroCents(props.ghesUnitPrice)}/month each
                          </div>
                        </div>
                        <div>${ghesBill}</div>
                      </div>
                      {props.bundledGhasBillableLicenseCount > 0 && (
                        <>
                          <hr className="my-2" />
                          <div className="d-flex flex-row gap-1">
                            <div className="d-flex flex-column flex-1">
                              <div>
                                {props.bundledGhasBillableLicenseCount.toLocaleString()} Advanced Security licenses
                              </div>
                              <div className="color-fg-muted">
                                ${dollarAmountHideZeroCents(props.bundledGhasUnitPrice)}/month each
                              </div>
                            </div>
                            <div>${ghasBill}</div>
                          </div>
                        </>
                      )}
                      {props.secretProtectionBillableLicenseCount > 0 && (
                        <>
                          <hr className="my-2" />
                          <div className="d-flex flex-row gap-1">
                            <div className="d-flex flex-column flex-1">
                              <div>
                                {props.secretProtectionBillableLicenseCount.toLocaleString()} Secret Protection licenses
                              </div>
                              <div className="color-fg-muted">
                                ${dollarAmountHideZeroCents(props.secretProtectionUnitPrice)}/month each
                              </div>
                            </div>
                            <div>${secretProtectionBill}</div>
                          </div>
                        </>
                      )}
                      {props.codeSecurityBillableLicenseCount > 0 && (
                        <>
                          <hr className="my-2" />
                          <div className="d-flex flex-row gap-1">
                            <div className="d-flex flex-column flex-1">
                              <div>
                                {props.codeSecurityBillableLicenseCount.toLocaleString()} Code Security licenses
                              </div>
                              <div className="color-fg-muted">
                                ${dollarAmountHideZeroCents(props.codeSecurityUnitPrice)}/month each
                              </div>
                            </div>
                            <div>${codeSecurityBill}</div>
                          </div>
                        </>
                      )}
                      <div className="d-flex flex-row-reverse gap-2 mt-2">
                        <Button className="btn-primary" onClick={() => setIsOpen(false)}>
                          Done
                        </Button>
                        <Button onClick={() => (window.location.href = billingDetailsHref)}>
                          View billing details
                        </Button>
                      </div>
                    </Dialog>
                  )}
                </Stack.Item>
              </Stack>
              <div>
                <div className={clsx('f3', styles.lineHeightSpacious)}>${totalBill}</div>
                <div className="text-small color-fg-muted pt-2">
                  Amount based on {billableLicenseCount} billable licenses, due by{' '}
                  {format(props.dueDate, 'MMMM d, yyyy')}.
                </div>
              </div>
            </Stack>
          </Stack.Item>
        </Stack>
      </div>
    )
  }

  return (
    <SummaryCard headerIconComponent={ServerIcon} title="Enterprise Server">
      {component}
    </SummaryCard>
  )
}
