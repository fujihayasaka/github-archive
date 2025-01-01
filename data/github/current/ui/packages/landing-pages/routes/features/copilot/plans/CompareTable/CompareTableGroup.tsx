import {useState} from 'react'

import {ChevronDownIcon} from '@primer/octicons-react'
import {Stack, Text} from '@primer/react-brand'

import type {CopilotFeature} from '../../../../../brand/lib/types/contentful'

import {PLAN_TYPES, type PlanType} from '../../_context/PlanTypeContext'

import {CompareTableRow} from './CompareTableRow'

type Props = {
  heading: string
  rows: CopilotFeature[]
  planType: PlanType
}

export function CompareTableGroup(props: Props) {
  const {heading, rows, planType} = props

  const [isExpanded, setIsExpanded] = useState(false)

  return (
    <Stack role="rowgroup" direction="vertical" gap="none" padding="none" className={isExpanded ? 'expanded' : ''}>
      <div role="row">
        <div role="cell" className="text-semibold mt-0 mt-md-5 pb-4 pb-md-3 d-none d-md-block">
          <Text size="300" weight="semibold">
            {heading}
          </Text>
        </div>

        <div role="cell" className="d-md-none">
          <button
            type="button"
            aria-expanded={isExpanded}
            className="position-relative text-semibold width-full lp-Pricing-features-toggle-btn border-bottom mt-0 mt-md-5 pb-4 pb-md-3"
            onClick={() => setIsExpanded(!isExpanded)}
          >
            <Text size="300" weight="semibold" className="events-none">
              {heading}

              <div className="lp-Pricing-features-icon position-absolute top-0 right-0 d-md-none">
                <ChevronDownIcon />
              </div>
            </Text>
          </button>
        </div>
      </div>

      <div className="lp-Pricing-features-box">
        {rows.map(row => (
          <CompareTableRow
            key={row.sys.id}
            contentfulContent={row}
            showFree={planType === PLAN_TYPES.Individual}
            showPro={planType === PLAN_TYPES.Individual}
            showProPlus={planType === PLAN_TYPES.Individual}
            showBusiness={planType === PLAN_TYPES.Business}
            showEnterprise={planType === PLAN_TYPES.Business}
          />
        ))}
      </div>
    </Stack>
  )
}
