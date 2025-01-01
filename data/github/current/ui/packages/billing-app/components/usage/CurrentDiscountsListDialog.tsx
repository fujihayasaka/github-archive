import React, {useState, useRef, Fragment} from 'react'
import {Text, Link, Box, Button} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {DiscountTargetType, DiscountType, UsagePeriod} from '../../enums'
import {formatMoneyDisplay} from '../../utils/money'
import {getTextForDiscount} from '../../utils/discount'
import {listStyle, Fonts, Spacing} from '../../utils/style'

import type {DiscountAmountsMap} from '../../types/discounts'
import useRoute from '../../hooks/use-route'
import {USAGE_ROUTE} from '../../routes'
import {GROUP_BY_SKU_TYPE, Products} from '../../constants'
interface Props {
  discountTargetAmounts: DiscountAmountsMap
  totalDiscount: number
  isOrganization: boolean
  isUser: boolean
  isEnterpriseOrgOwner: boolean
  isCopilotPremiumUsageReportEnabled: boolean
}

export const discountsListText = (isOrganization: boolean, isUser: boolean, isEnterpriseOrgOwner: boolean) => {
  if (isUser) {
    return 'Showing currently applied discounts for your account.'
  }
  if (isOrganization) {
    return 'Showing currently applied discounts for your organization.'
  }
  if (isEnterpriseOrgOwner) {
    return 'Showing currently applied discounts for your organization(s).'
  }
  return 'Showing currently applied discounts for your enterprise.'
}

export default function CurrentDiscountsListDialog({
  discountTargetAmounts,
  totalDiscount,
  isOrganization,
  isUser,
  isEnterpriseOrgOwner,
  isCopilotPremiumUsageReportEnabled,
}: Props) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const returnFocusRef = useRef(null)
  const discountsText = discountsListText(isOrganization, isUser, isEnterpriseOrgOwner)
  const {path: copilotUsageUrl} = useRoute(
    USAGE_ROUTE,
    {},
    {
      group: GROUP_BY_SKU_TYPE.toString(),
      period: UsagePeriod.THIS_MONTH.toString(),
      query: `product:${Products.copilot}`,
    },
  )

  return (
    <div data-testid="current-discounts-list-dialog-container">
      <Button variant="invisible" onClick={() => setIsDialogOpen(true)} sx={{fontSize: Fonts.FontSizeSmall}}>
        More details
      </Button>

      {isDialogOpen && (
        <Dialog
          onClose={() => setIsDialogOpen(false)}
          title="Current included usage"
          returnFocusRef={returnFocusRef}
          aria-labelledby="header"
          sx={{overflowY: 'auto'}}
        >
          <Box sx={{p: Spacing.StandardPadding}}>
            <div>
              <Text sx={{fontSize: 4}} data-testid="total-discount">
                {formatMoneyDisplay(totalDiscount)}
              </Text>
            </div>
            <Text
              as="p"
              sx={{
                color: 'fg.muted',
                borderTopColor: 'border.default',
                borderTopWidth: 1,
              }}
            >
              {discountsText}
            </Text>
            <Box as="ul" sx={{mb: Spacing.SmallPadding, overflowY: 'hidden'}}>
              {Object.values(DiscountTargetType).map(targetType => {
                const coercedTargetType = targetType as DiscountTargetType
                if (!discountTargetAmounts[coercedTargetType]) return

                const fixedDiscountAmount = discountTargetAmounts[coercedTargetType][DiscountType.FixedAmount]
                const percentageDiscountAmounts = discountTargetAmounts[coercedTargetType][DiscountType.Percentage]

                return (
                  <Fragment key={`${targetType}`}>
                    {fixedDiscountAmount && (
                      <Box
                        as="li"
                        sx={{
                          ...listStyle,
                        }}
                        key={`${coercedTargetType}-fixed-discount`}
                        data-testid={`${coercedTargetType}-fixed-discount`}
                      >
                        <Box sx={{flex: 1}}>
                          {getTextForDiscount(fixedDiscountAmount, coercedTargetType, DiscountType.FixedAmount).map(
                            (text, index) => (
                              // eslint-disable-next-line @eslint-react/no-array-index-key
                              <React.Fragment key={`${coercedTargetType}-fixed-discount-${index}`}>
                                {text}
                                <br />
                              </React.Fragment>
                            ),
                          )}
                        </Box>
                        <div>
                          <Text as="p" sx={{fontWeight: 'bold'}}>
                            {formatMoneyDisplay(fixedDiscountAmount.appliedAmount)}
                          </Text>
                        </div>
                      </Box>
                    )}
                    {percentageDiscountAmounts?.map((discountAmount, index) => {
                      return (
                        <Box
                          as="li"
                          sx={{...listStyle}}
                          // eslint-disable-next-line @eslint-react/no-array-index-key
                          key={`${coercedTargetType}-percentage-discount-${index}`}
                          data-testid={`${coercedTargetType}-percentage-discount-${index}`}
                        >
                          <Text
                            as="p"
                            sx={{
                              flex: 'auto',
                            }}
                          >
                            {getTextForDiscount(discountAmount, coercedTargetType, DiscountType.Percentage).join(' ')}
                          </Text>
                          <Text as="p" sx={{fontWeight: 'bold'}}>
                            {formatMoneyDisplay(discountAmount.appliedAmount)}
                          </Text>
                        </Box>
                      )
                    })}
                  </Fragment>
                )
              })}
            </Box>
            <Text
              as="p"
              sx={{
                color: 'fg.muted',
              }}
            >
              * As per current pricing
            </Text>
            {isCopilotPremiumUsageReportEnabled && (
              <Text
                as="p"
                sx={{
                  color: 'fg.muted',
                }}
                data-testid="copilot-premium-usage-report-download"
              >
                Download your Copilot premium request usage report{' '}
                <Link inline href={copilotUsageUrl}>
                  here
                </Link>
              </Text>
            )}
          </Box>
        </Dialog>
      )}
    </div>
  )
}
