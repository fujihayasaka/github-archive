import {Box, Heading, Text} from '@primer/react'

import {useDiscounts} from '../../hooks/discount'

import {formatMoneyDisplay} from '../../utils/money'
import {boxStyle, cardHeadingStyle, Fonts} from '../../utils/style'
import {CurrentDiscountsListDialog} from '.'

import type {EnabledProduct} from '../../types/products'
import {discountsListText} from './CurrentDiscountsListDialog'

const spendingContainerStyle = {
  display: 'flex',
  alignItems: 'flex-end',
  justifyContent: 'space-between',
  mb: 2,
}

interface DiscountUsageCardProps {
  enabledProducts: EnabledProduct[]
  isOrganization: boolean
  isUser: boolean
  isEnterpriseOrgOwner: boolean
  isCopilotPremiumUsageReportEnabled: boolean
}

export default function DiscountUsageCard({
  enabledProducts,
  isOrganization,
  isUser,
  isEnterpriseOrgOwner,
  isCopilotPremiumUsageReportEnabled,
}: DiscountUsageCardProps) {
  const {discounts, discountTargetAmounts} = useDiscounts({enabledProducts})

  const totalDiscount = discounts.reduce((acc, discount) => acc + discount.currentAmount, 0)

  return (
    <Box sx={boxStyle}>
      <Box sx={{display: 'flex', alignItems: 'center'}}>
        <Heading as="h2" sx={{...cardHeadingStyle, flex: 'auto'}}>
          Current included usage
        </Heading>
        {!isEnterpriseOrgOwner && (
          <CurrentDiscountsListDialog
            discountTargetAmounts={discountTargetAmounts}
            totalDiscount={totalDiscount}
            isOrganization={isOrganization}
            isUser={isUser}
            isEnterpriseOrgOwner={isEnterpriseOrgOwner}
            isCopilotPremiumUsageReportEnabled={isCopilotPremiumUsageReportEnabled}
          />
        )}
      </Box>
      <>
        <Box sx={spendingContainerStyle}>
          <div>
            <Text sx={{mr: 2, fontSize: 4}} data-testid="total-discount">
              {formatMoneyDisplay(totalDiscount)}
            </Text>
          </div>
        </Box>
        <Text as="p" sx={{mb: 0, color: 'fg.muted', fontSize: Fonts.FontSizeSmall}}>
          {discountsListText(isOrganization, isUser, isEnterpriseOrgOwner)}
        </Text>
      </>
    </Box>
  )
}
