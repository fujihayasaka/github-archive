import {format, parseISO} from 'date-fns'
import {useNavigation} from '../contexts/NavigationContext'
import {pluralize} from '../helpers/pluralize'
import {PaymentSummary} from './PaymentSummary'
import {Button, Stack} from '@primer/react'
import type {HeadingTag} from '../types/heading-tag'

export interface EnterpriseCloudPaymentSummaryProps {
  billingTermEndDate: string
  currentPayment: string
  enterpriseLicensesBillable: number
  headingAs?: HeadingTag
  isMonthly: boolean
  isTrial: boolean
  isVolumeLicensed: boolean
  isVssEnabled: boolean
  unitCost: string
}
export function EnterpriseCloudPaymentSummary(props: EnterpriseCloudPaymentSummaryProps) {
  const {basePath} = useNavigation()
  const formattedTermEndDate = format(parseISO(props.billingTermEndDate), 'MMMM d, yyyy')
  const paymentTermLabel = props.isTrial
    ? props.isMonthly
      ? 'Estimated monthly payment'
      : 'Estimated yearly payment'
    : props.isMonthly
      ? 'Monthly payment'
      : 'Yearly payment'

  const paymentSummaryBaseDescription = props.isVolumeLicensed
    ? `Amount based on ${pluralize(
        props.enterpriseLicensesBillable,
        'purchased license',
      )}, valid until ${formattedTermEndDate}.`
    : `Amount based on ${pluralize(
        props.enterpriseLicensesBillable,
        'billable license',
      )}, due by ${formattedTermEndDate}.`
  const paymentSummaryDescription = props.isVssEnabled
    ? `${paymentSummaryBaseDescription} This does not include Visual Studio subscriptions.`
    : paymentSummaryBaseDescription

  return (
    <PaymentSummary
      title={paymentTermLabel}
      currentPayment={props.currentPayment}
      description={paymentSummaryDescription}
      headingAs={props.headingAs}
      moreDetailsBody={
        <>
          <div className="f2 text-normal lh-default" data-testid="current-payment">
            {props.currentPayment}
          </div>
          <div className="text-normal f5 lh-default color-fg-muted my-2" data-testid="payment-description">
            {paymentSummaryDescription}
          </div>
          <Stack direction="vertical" className="border-top py-2">
            <Stack direction="horizontal" gap="condensed" className="width-full">
              <Stack direction="vertical" className="width-full">
                <span className="text-normal f5 lh-default" data-testid="ghec-billable-licenses">
                  {pluralize(props.enterpriseLicensesBillable, 'Enterprise license')}
                </span>
                <span className="text-normal f5 lh-default color-fg-muted" data-testid="ghec-unit-price">
                  {props.unitCost} each
                </span>
              </Stack>
              <span className="text-bold f5 lh-default" data-testid="ghec-billable-amount">
                {props.currentPayment}
              </span>
            </Stack>
          </Stack>
        </>
      }
      moreDetailsButtons={
        !props.isVolumeLicensed && (
          <Button
            as="a"
            href={`${basePath}/billing/usage?group=2&query=product:ghec`}
            data-testid="view-billing-details-btn"
          >
            View billing details
          </Button>
        )
      }
    />
  )
}
