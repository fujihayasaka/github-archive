import {LogoSuite, Image} from '@primer/react-brand'
import {LOGOS} from './Logos.data'

const COPY = {
  heading: 'GitHub is used by',
}

export default function Logos() {
  return (
    <div className="Logos">
      <LogoSuite className="Logos-logoSuite">
        <LogoSuite.Heading visuallyHidden>{COPY.heading}</LogoSuite.Heading>
        <LogoSuite.Logobar marquee marqueeSpeed="slow">
          {LOGOS.map((logo, index) => (
            <Image
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={index}
              src={logo.image}
              alt={logo.alt}
              style={{width: logo.width, height: 'auto'}}
              loading="lazy"
            />
          ))}
        </LogoSuite.Logobar>
      </LogoSuite>
    </div>
  )
}
