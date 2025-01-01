import {Heading, Text} from '@primer/react-brand'
import {CheckIcon, ChevronRightIcon, HorizontalRuleIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'

import AccordionItem from './../../Accordion/AccordionItem/AccordionItem'
import useAccordionStates from './../../Accordion/hooks/useAccordionStates'
import type {FeaturesTableProps} from './../FeaturesTable.types'

import FeaturesTableStyles from './../FeaturesTable.module.css'
import Styles from './FeaturesTableDesktop.module.css'

export type FeaturesTableDesktopProps = FeaturesTableProps

const defaultProps: Partial<FeaturesTableDesktopProps> = {}

const FeaturesTableDesktop: React.FC<FeaturesTableDesktopProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {title, tiers, features, aria} = initializedProps

  const {itemStates, updateItem} = useAccordionStates({items: features})

  return (
    <table className={Styles['FeaturesTableDesktop']}>
      <thead className={clsx(Styles['FeaturesTableDesktop__row'], Styles['FeaturesTableDesktop__head'])}>
        <tr>
          <th scope="col" className={Styles['FeaturesTableDesktop__column--left']}>
            <Heading as="h3" size="5">
              {title}
            </Heading>
          </th>

          {tiers.map((tier, index) => (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <th scope="col" key={`tier_${index}`}>
              <Heading as="h4" size="subhead-large">
                {tier}
              </Heading>
            </th>
          ))}
        </tr>
      </thead>

      <tbody>
        {features.map((feature, index) => {
          const isExpanded = !!itemStates[index]

          const headingDOM = (
            <div
              className={clsx(
                Styles['FeaturesTableDesktop__featureItemTitleBlock'],
                isExpanded && Styles['FeaturesTableDesktop__featureItemTitleBlock--expanded'],
              )}
            >
              <ChevronRightIcon size={16} className={Styles['FeaturesTableDesktop__featureItemTitleBlock-chevron']} />
              <Text variant="muted">{feature.title}</Text>
            </div>
          )

          const contentDOM = (
            <div
              className={clsx(
                Styles['FeaturesTableDesktop__featureItem-description'],
                Styles['FeaturesTableDesktop__column--left'],
              )}
            >
              {feature.description}
            </div>
          )

          return (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <tr key={`feature_${index}`} className={Styles['FeaturesTableDesktop__row--featureItem']}>
              <td className={Styles['FeaturesTableDesktop__column--left']}>
                <AccordionItem
                  heading={headingDOM}
                  content={contentDOM}
                  isExpanded={isExpanded}
                  onToggle={state => updateItem(index, state)}
                  className={Styles['FeaturesTableDesktop__featureItem-accordion']}
                />
              </td>

              {tiers.map((_, tierIndex) => {
                const availability = feature.availability[tierIndex]
                const availabilityBoolean = typeof availability === 'boolean' && availability
                const availabilityText = typeof availability === 'string' && availability

                return (
                  <td
                    // eslint-disable-next-line @eslint-react/no-array-index-key
                    key={`availability_${tierIndex}`}
                    className={clsx(
                      Styles['FeaturesTableDesktop__featureItemTier-availability'],
                      availabilityText
                        ? false
                        : availabilityBoolean
                          ? Styles['FeaturesTableDesktop__featureItemTier-availability--green']
                          : Styles['FeaturesTableDesktop__featureItemTier-availability--grey'],
                    )}
                  >
                    {availabilityText ? (
                      availabilityText
                    ) : availabilityBoolean ? (
                      <>
                        <CheckIcon size={24} />
                        <span className={FeaturesTableStyles['FeaturesTable__srOnly']}>{aria.included}</span>
                      </>
                    ) : (
                      <>
                        <HorizontalRuleIcon size={24} />
                        <span className={FeaturesTableStyles['FeaturesTable__srOnly']}>{aria.notIncluded}</span>
                      </>
                    )}
                  </td>
                )
              })}
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

export default FeaturesTableDesktop
