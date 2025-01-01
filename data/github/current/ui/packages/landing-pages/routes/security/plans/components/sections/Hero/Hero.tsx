import {useState, useEffect} from 'react'
import type React from 'react'
import {clsx} from 'clsx'

import {Hero as PrimerHero, Box} from '@primer/react-brand'
import type {PrimerComponentHero} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentHero'
import {ContentfulSubnav} from '@github-ui/swp-core/components/contentful/ContentfulSubnav'
import type {PrimerComponentSubnav} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentSubnav'

import PlanCard from '../../../../../../brand/components/PlanCard/PlanCard'
import type {PlanCardProps} from '../../../../../../brand/components/PlanCard/PlanCard'

import ImageBgDesktop from './../../../assets/images/background-desktop.webp'
import ImageBgMobile from './../../../assets/images/background-mobile.webp'

import SecurityStyles from '../../../../_styles/shared.module.css'
import Styles from './Hero.module.css'

export interface HeroProps {
  plans: PlanCardProps[]
  contentfulContent: PrimerComponentHero
  subnav?: PrimerComponentSubnav
}

const defaultProps: Partial<HeroProps> = {}

const Hero: React.FC<HeroProps> = props => {
  const initializedProps = {...defaultProps, ...props}

  const {plans, contentfulContent, subnav} = initializedProps
  const {heading, description, descriptionVariant} = contentfulContent.fields || {}

  const [isMounted, setIsMounted] = useState<boolean>(false)

  useEffect(() => {
    setIsMounted(true)
  }, [])

  return (
    <section id="hero" className={Styles['Hero']}>
      <div
        className={clsx(Styles['Hero__background'], !isMounted && Styles['Hero__background--isHidden'])}
        style={{
          ['--backgroundUrl-desktop']: `url("${ImageBgDesktop}")`,
          ['--backgroundUrl-mobile']: `url("${ImageBgMobile}")`,
        }}
      />

      <div className={Styles['Hero__container']}>
        <Box className={SecurityStyles['SubNav__spacer']} />

        {subnav ? <ContentfulSubnav component={subnav} linkVariant="default" /> : null}

        <div className={Styles['Hero__content']}>
          <PrimerHero align="center" className={Styles['Hero__heroBlock']} data-hpc>
            <PrimerHero.Heading className={Styles['Hero__title']}>{heading}</PrimerHero.Heading>
            <PrimerHero.Description variant={descriptionVariant}>{description}</PrimerHero.Description>
          </PrimerHero>

          <div className={Styles['PricingPlans']}>
            {plans.map((plan, index) => (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <PlanCard key={`plan_${index}`} {...plan} />
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}

export default Hero
