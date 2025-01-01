import {CheckIcon} from '@primer/octicons-react'
import {Text, Label, Radio, Stack} from '@primer/react'
import type {PlanInfo} from '../../../types'
import styles from './PlansRadioGroup.module.css'

interface PlansRadioGroupProps {
  planInfo: PlanInfo
  onPlanChange: (planId: string) => void
  selectedPlanId?: string
}

export default function PlansRadioGroup({planInfo, onPlanChange, selectedPlanId}: PlansRadioGroupProps) {
  return (
    <Stack gap="normal" className="border-bottom color-border-muted" data-testid="plans-radio-group">
      {planInfo.plans.map((plan, idx) => (
        <Stack
          key={plan.id}
          gap="condensed"
          direction="horizontal"
          className={idx === planInfo.plans.length - 1 ? 'pb-3' : ''}
        >
          <Radio
            aria-describedby="price-yearly"
            name="plan"
            value={plan.id}
            id={plan.id}
            checked={selectedPlanId === plan.id}
            onChange={() => onPlanChange(plan.id)}
          />
          <Stack gap="condensed" direction="vertical" className="width-full">
            <Stack gap="condensed" direction="horizontal">
              <Stack
                gap={{narrow: 'none', regular: 'condensed', wide: 'condensed'}}
                direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}}
                justify="space-between"
                className="width-full"
              >
                <Stack gap="none" direction="vertical" className="width-full">
                  <label htmlFor={plan.id} className="text-bold">
                    {plan.name}{' '}
                    {plan.isPaid && plan.hasFreeTrial && <Label className="ml-1">Free trial available</Label>}
                  </label>
                  <Text size="small" className="color-fg-muted mt-1">
                    {plan.description}
                  </Text>
                </Stack>
                <span className="color-fg-muted flex-shrink-0" data-testid="plan-price-info">
                  {plan.isPaid && (
                    <>
                      <span>{plan.price}</span>
                      {plan.perUnit && <span> {`/ ${plan.unitName}`}</span>}
                      <span>{planInfo.isUserBilledMonthly ? ' / month' : ' / year'}</span>
                    </>
                  )}
                  {!plan.isPaid && !plan.directBilling && <span>$0</span>}
                </span>
              </Stack>
            </Stack>
            {selectedPlanId === plan.id &&
              (plan.forOrganizationsOnly || plan.forUsersOnly || plan.bullets.length > 0) && (
                <Stack gap="condensed">
                  {plan.forOrganizationsOnly && <div>For organizations only</div>}
                  {plan.forUsersOnly && <div>For users only</div>}

                  {plan.bullets.length > 0 && (
                    <ul className="list-style-none d-flex flex-column gap-1">
                      {plan.bullets.map(bullet => (
                        <li key={bullet} className="d-flex gap-2">
                          <CheckIcon className={styles.CheckIcon} />
                          <Text as="span" size="small">
                            {bullet}
                          </Text>
                        </li>
                      ))}
                    </ul>
                  )}
                </Stack>
              )}
          </Stack>
        </Stack>
      ))}
    </Stack>
  )
}
