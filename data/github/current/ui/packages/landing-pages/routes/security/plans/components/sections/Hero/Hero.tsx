import {useState, useEffect} from 'react'
import type React from 'react'
import {Hero as PrimerHero} from '@primer/react-brand'
import {clsx} from 'clsx'

import SecuritySubNav from './../../../../_components/SecuritySubNav/SecuritySubNav'
import PlanCard from './../../../../_components/PlanCard/PlanCard'
import type {PlanCardProps} from '../../../../_components/PlanCard/PlanCard'
import {ROUTES} from './../../../../_utils/config'
import ImageBgDesktop from './../../../assets/images/background-desktop.webp'
import ImageBgMobile from './../../../assets/images/background-mobile.webp'

import Styles from './Hero.module.css'

export interface HeroProps {
  title: string
  label: string
  plans: PlanCardProps[]
}

const defaultProps: Partial<HeroProps> = {}

const Hero: React.FC<HeroProps> = props => {
  const initializedProps = {...defaultProps, ...props}

  const {title, label, plans} = initializedProps
  const [isMounted, setIsMounted] = useState<boolean>(false)

  useEffect(() => {
    setIsMounted(true)
  }, [])

  return (
    <section id="hero" className={Styles['Hero']}>
      <div
        className={clsx(Styles['Hero__background'], !isMounted && Styles['Hero__background--isHidden'])}
        style={
          {
            ['--backgroundUrl-desktop']: `url("${ImageBgDesktop}")`,
            ['--backgroundUrl-mobile']: `url("${ImageBgMobile}")`,
          } as React.CSSProperties
        }
      />

      <div className={Styles['Hero__container']}>
        <SecuritySubNav currentUrl={ROUTES.plans} />

        <div className={Styles['Hero__content']}>
          <PrimerHero align="center" className={Styles['Hero__heroBlock']} data-hpc>
            <PrimerHero.Label>{label}</PrimerHero.Label>
            <PrimerHero.Heading className={Styles['Hero__title']}>{title}</PrimerHero.Heading>
          </PrimerHero>

          <div className={Styles['Hero__plans']}>
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
