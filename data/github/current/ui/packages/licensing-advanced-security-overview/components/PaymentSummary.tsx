import {Stack, Button, Dialog} from '@primer/react'
import {useState} from 'react'
import {clsx} from 'clsx'
import styles from './PaymentSummary.module.css'
import type {Sku} from '../utils'
import {format} from 'date-fns'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'

export interface PaymentSummaryProps {
  billingCycle: string
  billableLicenses: number
  billingTermEndDate: string
  currentPayment: string
  isBundled: boolean
  isMeteredLicensed: boolean
  skus: Sku[]
}

export function PaymentSummary({
  billingCycle,
  billableLicenses,
  billingTermEndDate,
  currentPayment,
  isBundled,
  isMeteredLicensed,
  skus,
}: PaymentSummaryProps) {
  const [isDialogOpen, setIsDialogOpen] = useState<boolean>(false)
  const title = isMeteredLicensed ? 'Estimated next payment' : `${billingCycle} payment`
  const description = () => {
    if (isMeteredLicensed) {
      return `Amount based on ${billableLicenses.toLocaleString()} billable licenses, due by ${format(
        billingTermEndDate,
        'MMMM d, yyyy',
      )}.`
    }
    return `Amount based on ${billableLicenses.toLocaleString()} purchased licenses.`
  }
  const formatLicenseDisplay = (sku: Sku): string => {
    const count = sku.billableLicenses.toLocaleString()
    const name = sku.name

    if (isBundled) {
      return `${count} ${name}`
    }

    return `${count} ${name} licenses`
  }
  const {basePath} = useNavigation()
  const usageDetailsHref = `${basePath}/billing/usage?group=2&query=product:ghas`
  return (
    <Stack
      direction="vertical"
      gap="condensed"
      padding="none"
      align="start"
      className={clsx(styles.wrapper)}
      data-testid="payment-summary"
    >
      <Stack
        direction="horizontal"
        gap="condensed"
        padding="none"
        align="center"
        data-testid="payment-summary-header"
        className="width-full"
      >
        <Stack.Item grow>
          <h4 className="f5" data-testid="payment-summary-title">
            {title}
          </h4>
        </Stack.Item>
        <Stack.Item>
          <Button data-testid="more-details-btn" variant="invisible" onClick={() => setIsDialogOpen(!isDialogOpen)}>
            More details
          </Button>
          {isDialogOpen && (
            <Dialog width="large" title={title} onClose={() => setIsDialogOpen(false)}>
              <div className="f2 text-normal lh-default" data-testid="current-payment">
                {currentPayment}
              </div>
              <div className="text-normal f6 lh-default color-fg-muted my-2" data-testid="payment-description">
                {description()}
              </div>
              {skus.map(sku => (
                <Stack direction="vertical" className="border-top py-2" key={sku.sku}>
                  <Stack direction="horizontal" gap="condensed" className="width-full">
                    <Stack direction="vertical" className="width-full">
                      <span className="text-normal f6 lh-default" data-testid={`${sku.sku}-billable-licenses`}>
                        {formatLicenseDisplay(sku)}
                      </span>
                      <span className="text-normal f6 lh-default color-fg-muted" data-testid={`${sku.sku}-unit-price`}>
                        ${sku.unitPrice}/month each
                      </span>
                    </Stack>
                    <span className="text-bold f6 lh-default" data-testid={`${sku.sku}-billable-amount`}>
                      ${sku.billableAmount}
                    </span>
                  </Stack>
                </Stack>
              ))}
              <div className="d-flex flex-row-reverse gap-2 mt-2">
                <Button className="btn-primary" onClick={() => setIsDialogOpen(false)}>
                  Done
                </Button>
                {isMeteredLicensed && (
                  <Button as="a" href={usageDetailsHref} data-testid="view-usage-details-btn">
                    View billing details
                  </Button>
                )}
              </div>
            </Dialog>
          )}
        </Stack.Item>
      </Stack>
      <div className="f3 text-normal lh-default" data-testid="billable-amount">
        {currentPayment}
      </div>
      <div className="f5 color-fg-muted" data-testid="billable-amount-description">
        {description()}
      </div>
    </Stack>
  )
}
