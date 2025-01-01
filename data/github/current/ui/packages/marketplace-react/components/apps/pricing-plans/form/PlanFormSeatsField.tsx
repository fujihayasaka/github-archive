import {FormControl, TextInput} from '@primer/react'
import {usePlanForm} from './PlanFormContext'
import styles from './PlanFormSeatsField.module.css'

export default function PlanFormSeatsField() {
  const {planInfo, plan, seatQuantity, setSeatQuantity} = usePlanForm()

  if (!plan.isPaid) return null

  return (
    <>
      {plan.perUnit && (
        <FormControl id="quantity">
          <FormControl.Label htmlFor="quantity" className="text-normal" as="label">
            {`Number of ${plan.unitName}s`}
          </FormControl.Label>
          <TextInput
            type="number"
            value={seatQuantity}
            name="quantity"
            min="0"
            max="100000"
            onChange={e => setSeatQuantity(parseInt(e.target.value))}
            data-testid="seat-quantity-input"
            className={styles.TextInput}
          />
        </FormControl>
      )}
      <div className={'border-bottom border-top py-2 d-flex flex-items-baseline flex-justify-between'}>
        <div className="d-flex flex-items-baseline">
          <span className="f2 mr-2" data-testid="plan-form-price">
            {plan.price}
          </span>
          <span className="text color-fg-muted">
            {plan.perUnit && <span> {`/ ${plan.unitName}`}</span>}
            <span>{planInfo.isUserBilledMonthly ? ' / month' : ' / year'}</span>
          </span>
        </div>
      </div>
    </>
  )
}
