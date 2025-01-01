import {Button, CTABanner as PrimerCtaBanner} from '@primer/react-brand'

import Styles from './CtaBanner.module.css'

export interface CtaBannerProps {
  title: string
  description: string
  cta: {
    label: string
    href: string
  }
}

const defaultProps: Partial<CtaBannerProps> = {}

const CtaBanner: React.FC<CtaBannerProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {title, description, cta} = initializedProps

  return (
    <section id="ctaBanner" className={Styles['CtaBanner']}>
      <div className={Styles['CtaBanner__container']}>
        <PrimerCtaBanner align="center" hasShadow={false} className={Styles['CtaBanner__content']}>
          <PrimerCtaBanner.Heading as="h3" size="4">
            {title}
          </PrimerCtaBanner.Heading>
          <PrimerCtaBanner.Description variant="muted">{description}</PrimerCtaBanner.Description>

          <PrimerCtaBanner.ButtonGroup>
            <Button as="a" href={cta.href}>
              {cta.label}
            </Button>
          </PrimerCtaBanner.ButtonGroup>
        </PrimerCtaBanner>
      </div>
    </section>
  )
}

export default CtaBanner
