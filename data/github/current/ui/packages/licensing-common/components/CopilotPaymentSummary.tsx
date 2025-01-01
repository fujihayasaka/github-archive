import {Stack, LinkButton, Button, Dialog} from '@primer/react'
import {clsx} from 'clsx'
import styles from './CopilotPaymentSummary.module.css'
import {useState} from 'react'
import type {Sku} from '../copilot-types'

export interface CopilotPaymentSummaryProps {
  billingTermEndDate: string
  totalCost: number
  skus: Sku[]
  headingLevel?: 'h2' | 'h3'
}

const capitalizeName = (sku: string) => sku.charAt(0).toUpperCase() + sku.slice(1)
const dollarAmount = (amount: number) => {
  return amount.toLocaleString('en-US', {minimumFractionDigits: 2})
}

export function CopilotPaymentSummary({billingTermEndDate, totalCost, skus, headingLevel}: CopilotPaymentSummaryProps) {
  const [isOpen, setIsOpen] = useState(false)
  // period=3 is for the current billing term
  // group=2 is for Copilot
  // query=product:copilot is for the Copilot product
  const billingDetailsHref = './billing/usage?period=3&group=2&query=product:copilot'
  const skuTotal = (sku: Sku) => sku.consumedLicenses * sku.unitPrice
  const skuTotalFormatted = (sku: Sku) => dollarAmount(skuTotal(sku))
  const totalLicenses = skus.reduce((acc, sku) => acc + sku.consumedLicenses, 0)
  const totalLicensesFormatted = totalLicenses.toLocaleString()
  const totalBillFormatted = dollarAmount(totalCost)
  const HeadingTag = headingLevel as keyof JSX.IntrinsicElements // Dynamically set the heading tag

  return (
    <Stack direction="vertical" gap="condensed" padding="none" align="start" className={clsx(styles.wrapper)}>
      <Stack direction="horizontal" gap="condensed" padding="none" align="center" className={clsx(styles.fillWidth)}>
        <Stack.Item grow>
          <HeadingTag className="pt-0 h5" data-testid="payment-summary-title">
            Estimated next payment
          </HeadingTag>
        </Stack.Item>
        <Stack.Item>
          <Button
            variant="invisible"
            className="text-bold"
            data-testid="payment-summary-details-button"
            onClick={() => setIsOpen(!isOpen)}
          >
            More details
          </Button>
          {isOpen && (
            <Dialog
              width="large"
              onClose={() => setIsOpen(false)}
              title="Estimated next payment"
              data-testid="payment-summary-details-dialog"
            >
              <Stack direction="vertical" gap="condensed" padding="none" align="start">
                <div className={clsx('f3', styles.lineHeightSpacious)} data-testid="billable-amount">
                  ${totalBillFormatted}
                </div>
                <div className="color-fg-muted" data-testid="billable-amount-description">
                  Amount based on {totalLicensesFormatted} billable licenses, due by {billingTermEndDate}.
                </div>
                {skus.map(sku => (
                  <Stack
                    direction="horizontal"
                    gap="condensed"
                    padding="none"
                    align="start"
                    className={clsx(styles.fillWidth, styles.divider, 'pt-2')}
                    key={sku.sku}
                  >
                    <Stack.Item grow>
                      <div>
                        <div>
                          {sku.consumedLicenses} Copilot {capitalizeName(sku.sku)} licenses
                        </div>
                        <div className="color-fg-muted">${dollarAmount(sku.unitPrice)}/month each</div>
                      </div>
                    </Stack.Item>
                    <Stack.Item>
                      <div>${skuTotalFormatted(sku)}</div>
                    </Stack.Item>
                  </Stack>
                ))}
              </Stack>
              <div className="d-flex flex-row-reverse gap-2 mt-2">
                <Button variant="primary" onClick={() => setIsOpen(false)} data-testid="done-button">
                  Done
                </Button>
                <LinkButton href={billingDetailsHref}>View billing details</LinkButton>
              </div>
            </Dialog>
          )}
        </Stack.Item>
      </Stack>
      <div className={clsx('f3', styles.lineHeightSpacious)} data-testid="billable-amount">
        ${totalBillFormatted}
      </div>
      <div className="color-fg-muted" data-testid="billable-amount-description">
        Amount based on {totalLicensesFormatted} billable licenses, due by {billingTermEndDate}.
      </div>
    </Stack>
  )
}
