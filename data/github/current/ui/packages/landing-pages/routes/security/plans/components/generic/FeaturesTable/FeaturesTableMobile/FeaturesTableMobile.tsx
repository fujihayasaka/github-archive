import {Heading, Text} from '@primer/react-brand'
import {CheckIcon, ChevronDownIcon, HorizontalRuleIcon} from '@primer/octicons-react'
import {useMemo} from 'react'
import {clsx} from 'clsx'

import Accordion from './../../Accordion/Accordion'
import useAccordionStates from './../../Accordion/hooks/useAccordionStates'
import type {FeaturesTableProps} from './../FeaturesTable.types'

import Styles from './FeaturesTableMobile.module.css'

export type FeaturesTableMobileProps = FeaturesTableProps

const defaultProps: Partial<FeaturesTableMobileProps> = {}

const FeaturesTableMobile: React.FC<FeaturesTableMobileProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {title, tiers, features} = initializedProps

  const {itemStates, updateItem} = useAccordionStates({items: features})

  const featureItems = useMemo(() => {
    return features.map((feature, index) => {
      const isExpanded = !!itemStates[index]

      const headingDOM = (
        <div
          className={clsx(
            Styles['FeaturesTableMobile__featureItemTitleBlock'],
            isExpanded && Styles['FeaturesTableMobile__featureItemTitleBlock--expanded'],
          )}
        >
          <Heading size="subhead-large" as="h4" className={Styles['FeaturesTableMobile__featureItemTitleBlock-title']}>
            {feature.title}
          </Heading>
          <ChevronDownIcon size={24} className={Styles['FeaturesTableMobile__featureItemTitleBlock-chevron']} />
        </div>
      )

      const contentDOM = (
        <>
          <Text as="p" className={Styles['FeaturesTableMobile__featureItemTitleBlock-description']} variant="muted">
            {feature.description}
          </Text>

          {tiers.map((tier, tierIndex) => {
            const availability = feature.availability[tierIndex]
            const availabilityBoolean = typeof availability === 'boolean' && availability
            const availabilityText = typeof availability === 'string' && availability

            return (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <div key={`tier_${tierIndex}`} className={Styles['FeaturesTableMobile__featureItemTier']}>
                <Text className={Styles['FeaturesTableMobile__featureItemTier-label']} weight="semibold">
                  {tier}
                </Text>

                <div
                  className={clsx(
                    Styles['FeaturesTableMobile__featureItemTier-availability'],
                    availabilityText
                      ? false
                      : availabilityBoolean
                        ? Styles['FeaturesTableMobile__featureItemTier-availability--green']
                        : Styles['FeaturesTableMobile__featureItemTier-availability--grey'],
                  )}
                >
                  {availabilityText ? (
                    availabilityText
                  ) : availabilityBoolean ? (
                    <CheckIcon size={24} />
                  ) : (
                    <HorizontalRuleIcon size={24} />
                  )}
                </div>
              </div>
            )
          })}
        </>
      )

      return {
        heading: headingDOM,
        content: contentDOM,
        isExpanded,
      }
    })
  }, [features, tiers, itemStates])

  return (
    <div className={Styles['FeaturesTableMobile']}>
      <Heading size="5" as="h3" className={Styles['FeaturesTableMobile__title']}>
        {title}
      </Heading>

      <div>
        <Accordion
          items={featureItems}
          itemClassName={Styles['FeaturesTableMobile__featureItem']}
          onItemToggle={updateItem}
        />
      </div>
    </div>
  )
}

export default FeaturesTableMobile
