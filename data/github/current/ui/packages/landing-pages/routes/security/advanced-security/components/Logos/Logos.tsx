import {toSnakeCase} from '@github-ui/swp-core/lib/utils/analytics'
import {LogoSuite, Image} from '@primer/react-brand'

import Styles from './Logos.module.css'

interface LogoData {
  src: string
  alt: string
  height: string | number
}

interface LogosProps {
  data: readonly LogoData[] | LogoData[]
}

export default function Logos({data}: LogosProps) {
  return (
    <div className={Styles['Logos']}>
      <LogoSuite className={Styles['Logos-logoSuite']} hasDivider={false}>
        <LogoSuite.Heading visuallyHidden>GitHub is used by</LogoSuite.Heading>
        <LogoSuite.Logobar marquee marqueeSpeed="slow">
          {data.map(logo => (
            <Image
              key={`logo_${toSnakeCase(logo.alt)}`}
              src={logo.src}
              alt={logo.alt}
              style={{height: logo.height}}
              loading="lazy"
            />
          ))}
        </LogoSuite.Logobar>
      </LogoSuite>
    </div>
  )
}
