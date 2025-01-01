import {useEffect, useState} from 'react'
import {Button, IconButton} from '@primer/react'
import {AlertIcon, DashIcon, PlusIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import styles from './ManageSeats.module.css'
import {type SeatPriceCheckResult, checkSeatPrice} from '../services/seats'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {useNavigation} from '../contexts/NavigationContext'
import type {PaymentMethod} from '../types/payment-method'
import {ManageSeatsPaymentMethod} from './ManageSeatsPaymentMethod'
import {pluralize} from '../helpers/pluralize'

const MAX_DELTA = 300
const MAX_TRIAL_SEATS = 50

export interface ManageSeatsProps {
  analyticsEventCategory: string
  analyticsRefPage?: string
  currentPrice: string
  isMonthlyPlan: boolean
  isTrial: boolean
  paymentMethod: PaymentMethod
  onCancelClick: () => void
  onSaveClick: (newSeats: number) => void
  licensesPurchased: number
  seatsConsumed: number
  seatsPath: string
}
export function ManageSeats({
  analyticsEventCategory,
  analyticsRefPage,
  currentPrice,
  isMonthlyPlan,
  isTrial,
  paymentMethod,
  onCancelClick,
  onSaveClick,
  licensesPurchased,
  seatsConsumed,
  seatsPath,
}: ManageSeatsProps) {
  const [newSeats, setNewSeats] = useState<number>(licensesPurchased)
  const [seatPriceCheckResult, setSeatPriceCheckResult] = useState<SeatPriceCheckResult | null>(null)
  const [minMaxError, setMinMaxError] = useState<string | null>(null)
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const {basePath} = useNavigation()

  const paymentTermLabel = isMonthlyPlan
    ? isTrial
      ? 'Estimated monthly payment'
      : 'Monthly payment'
    : isTrial
      ? 'Estimated yearly payment'
      : 'Yearly payment'
  const min = Math.max(licensesPurchased - MAX_DELTA, Math.max(seatsConsumed, 1))
  const max = isTrial ? MAX_TRIAL_SEATS : licensesPurchased + MAX_DELTA

  const validateSeatCount = (newCount: number) => {
    setMinMaxError(null)

    if (newCount > max) {
      if (isTrial) {
        setMinMaxError(`You may have a maximum of ${MAX_TRIAL_SEATS} licenses during your trial.`)
      } else {
        setMinMaxError(`You can only add or remove up to ${MAX_DELTA} licenses at a time`)
      }
      setNewSeats(max)
      return false
    }
    if (newCount < min) {
      setMinMaxError(`You need at least ${pluralize(min, 'license')}`)
      setNewSeats(min)
      return false
    }

    return true
  }

  const onAddSeatClick = () => {
    sendClickAnalyticsEvent({
      category: analyticsEventCategory,
      action: 'click_to_increase_seats_number',
      label: `ref_cta:increase_seats_number;ref_loc:enterprise_licensing${
        analyticsRefPage ? `;ref_page:${analyticsRefPage}` : ''
      }`,
    })
    if (validateSeatCount(newSeats + 1)) {
      setNewSeats(newSeats + 1)
    }
  }
  const onRemoveSeatClick = () => {
    sendClickAnalyticsEvent({
      category: analyticsEventCategory,
      action: 'click_to_decrease_seats_number',
      label: `ref_cta:decrease_seats_number;ref_loc:enterprise_licensing${
        analyticsRefPage ? `;ref_page:${analyticsRefPage}` : ''
      }`,
    })
    if (validateSeatCount(newSeats - 1)) {
      setNewSeats(newSeats - 1)
    }
  }
  const onNewSeatsClicked = () => {
    sendClickAnalyticsEvent({
      category: analyticsEventCategory,
      action: 'click_on_seats_input',
      label: `ref_cta:seats_input;ref_loc:enterprise_licensing${
        analyticsRefPage ? `;ref_page:${analyticsRefPage}` : ''
      }`,
    })
  }
  const onNewSeatsChanged = (newCount: number) => {
    setNewSeats(newCount) // update the field even if it's not a valid new count; weird otherwise
  }

  const handleSaveClick = () => {
    if (validateSeatCount(newSeats)) {
      onSaveClick(newSeats)
    }
  }
  const handleCancelClick = () => {
    onCancelClick()
  }

  useEffect(() => {
    const seatsUrl = `${basePath}${seatsPath}`
    // eslint-disable-next-line github/no-then
    checkSeatPrice(seatsUrl, newSeats).then(setSeatPriceCheckResult)
  }, [basePath, newSeats, seatsPath])

  return (
    <div className="pt-4 px-4 pb-4 d-flex flex-1 flex-column text-normal color-fg-default" data-testid="manage-seats">
      <div className="d-flex flex-row flex-wrap col-12">
        <div className={clsx('d-flex', 'flex-column', 'flex-wrap', 'col-4', 'p-2', styles.manageSeatsCol)}>
          <h5>Total licenses</h5>
          <div className="my-2">
            <div className="d-flex">
              <IconButton
                icon={DashIcon}
                className="px-3 rounded-right-0 border-right-0"
                aria-label="Remove license"
                onClick={onRemoveSeatClick}
                data-testid="remove-seat-button"
              />
              <input
                type="number"
                value={newSeats}
                min={min}
                max={max}
                className={clsx('form-control', styles.newSeatsInput)}
                aria-label="Number of licenses"
                onChange={e => onNewSeatsChanged(parseInt(e.target.value, 10))}
                onClick={onNewSeatsClicked}
                onBlur={e => validateSeatCount(parseInt(e.target.value, 10))}
                data-testid="new-seats-input"
              />
              <IconButton
                icon={PlusIcon}
                className="px-3 rounded-left-0 border-left-0"
                aria-label="Add license"
                onClick={onAddSeatClick}
                data-testid="add-seat-button"
              />
            </div>
            {minMaxError && (
              <p className="f6 color-fg-muted mt-2 mb-0">
                <AlertIcon className="mr-2 color-fg-attention" />
                {minMaxError}
              </p>
            )}
          </div>
          {!minMaxError && (
            <p className="text-small color-fg-muted">You currently have {pluralize(licensesPurchased, 'license')}</p>
          )}
        </div>
        <div className={clsx('d-flex', 'flex-column', 'col-4', 'p-2', styles.manageSeatsCol)}>
          <h5 data-testid="payment-term-label">{paymentTermLabel}</h5>
          <span className="f2">{seatPriceCheckResult?.current_price || currentPrice}</span>
          {!isTrial && seatPriceCheckResult?.payment_increase && (
            <p className="text-small color-fg-muted my-2">
              Your payment increases by{' '}
              <strong className="color-fg-danger">{seatPriceCheckResult?.payment_increase}</strong>
            </p>
          )}
          {!isTrial && seatPriceCheckResult?.payment_decrease && (
            <p className="text-small color-fg-muted my-2">
              Your payment decreases by{' '}
              <strong className="color-fg-success">{seatPriceCheckResult?.payment_decrease}</strong>
            </p>
          )}
        </div>
        <div className={clsx('d-flex', 'flex-column', 'col-4', 'p-2', styles.manageSeatsCol)}>
          <h5>Due today</h5>
          <span className="f2">{seatPriceCheckResult?.payment_due || '—'}</span>
          <ManageSeatsPaymentMethod paymentMethod={paymentMethod} />
        </div>
      </div>
      <div className="d-flex flex-row flex-wrap flex-justify-end">
        <div className="d-flex flex-column flex-auto px-2 text-small color-fg-muted">
          <p className="mb-1">{seatPriceCheckResult?.payment_due_notice}</p>
          <p className="mb-1">{seatPriceCheckResult?.sales_tax_notice}</p>
        </div>
        <div className="d-flex flex-row">
          <span className="mr-3">
            <Button onClick={handleCancelClick} data-testid="manage-seats-cancel-button">
              Cancel
            </Button>
          </span>
          <Button variant="primary" onClick={handleSaveClick} data-testid="manage-seats-save-button">
            Confirm licenses
          </Button>
        </div>
      </div>
    </div>
  )
}
