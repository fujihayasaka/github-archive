import {useState} from 'react'
import {Button, Dialog, Heading, Stack} from '@primer/react'
import type {HeadingTag} from '../types/heading-tag'
import {clsx} from 'clsx'
import styles from './PaymentSummary.module.css'

export interface PaymentSummaryProps {
  title: string
  currentPayment: string
  description?: string
  headingAs?: HeadingTag
  moreDetailsBody?: React.ReactNode
  moreDetailsButtons?: React.ReactNode
}

export function PaymentSummary({
  title,
  currentPayment,
  description,
  headingAs = 'h3',
  moreDetailsBody,
  moreDetailsButtons,
}: PaymentSummaryProps) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)

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
          <Heading as={headingAs} data-testid="payment-summary-title" className={clsx('f5', styles.titleHeader)}>
            {title}
          </Heading>
        </Stack.Item>
        {moreDetailsBody != null && (
          <Stack.Item>
            <Button data-testid="more-details-btn" variant="invisible" onClick={() => setIsDialogOpen(true)}>
              More details
            </Button>
            {isDialogOpen && (
              <Dialog title={title} width="large" onClose={() => setIsDialogOpen(false)}>
                {moreDetailsBody}
                <div className="d-flex flex-row-reverse gap-2 mt-2">
                  <Button className="btn-primary" onClick={() => setIsDialogOpen(false)}>
                    Done
                  </Button>
                  {moreDetailsButtons != null && moreDetailsButtons}
                </div>
              </Dialog>
            )}
          </Stack.Item>
        )}
      </Stack>
      <div className="f3 text-normal lh-default" data-testid="billable-amount">
        {currentPayment}
      </div>
      <div className="f6 color-fg-muted" data-testid="billable-amount-description">
        {description}
      </div>
    </Stack>
  )
}
