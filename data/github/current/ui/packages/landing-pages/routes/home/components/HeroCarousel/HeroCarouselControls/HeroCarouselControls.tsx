import {useCallback, useEffect, useState} from 'react'
import Toggle from '../../Toggle/Toggle'
import type {HeroScreenId} from '../HeroCarousel.data'
import {Text} from '@primer/react-brand'
import {checkPrefersReducedMotion} from '../../../../../lib/utils/platform'
import {wait} from '../../../utils/time'

import {TRANSITION_DURATION} from '../../PlayButton/PlayButton'

export interface HeroCarouselControlsProps {
  items: Array<{
    label: string
    value: HeroScreenId
    description: string
  }>
  currentIndex: number
  onChange: (screenIndex: number) => void
  toggleAriaLabel: string
}

const defaultProps: Partial<HeroCarouselControlsProps> = {}

const HeroCarouselControls: React.FC<HeroCarouselControlsProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {items, currentIndex, onChange, toggleAriaLabel} = initializedProps

  const [isMounted, setIsMounted] = useState<boolean>(false)
  const [shouldReduceMotion, setShouldReduceMotion] = useState<boolean>(false)
  const [visibleIndex, setVisibleIndex] = useState<number>(currentIndex)
  const [isDescriptionVisible, setIsDescriptionVisible] = useState<boolean>(true)

  const handleOnToggle = useCallback(
    (screenId: HeroScreenId) => {
      onChange(items.findIndex(item => item.value === screenId))
    },
    [items, onChange],
  )

  useEffect(() => {
    // Add delay to allow the transition to complete
    const proceed = async () => {
      if (shouldReduceMotion) {
        setVisibleIndex(currentIndex)
        return
      }

      setIsDescriptionVisible(false)
      await wait((TRANSITION_DURATION / 2) * 1000)

      setVisibleIndex(currentIndex)
      await wait((TRANSITION_DURATION / 2) * 1000)

      setIsDescriptionVisible(true)
    }

    proceed()
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentIndex])

  useEffect(() => {
    setIsMounted(true)
  }, [])

  useEffect(() => {
    if (!isMounted) return
    setShouldReduceMotion(checkPrefersReducedMotion())
  }, [isMounted])

  return (
    <div className="HeroCarouselControls">
      <ul className="HeroCarouselControls-breadcrumbs">
        {items.map((item, index) => (
          <li
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={`item_${index}`}
            className={`HeroCarouselControls-breadcrumbsItem ${
              currentIndex === index ? 'HeroCarouselControls-breadcrumbsItem--selected' : ''
            }`}
          />
        ))}
      </ul>

      <Toggle
        items={items}
        onToggle={value => handleOnToggle(value as HeroScreenId)}
        currentIndex={currentIndex}
        ariaLabel={toggleAriaLabel}
      />

      <Text
        as="p"
        size="200"
        weight="medium"
        className={`HeroCarouselControls-description ${
          !isDescriptionVisible ? 'HeroCarouselControls-description--hidden' : ''
        }`}
      >
        {items[visibleIndex]?.description}
      </Text>
    </div>
  )
}

export default HeroCarouselControls
