import {AnchorNav, Box, Hero, Image, LogoSuite} from '@primer/react-brand'
import heroVisual from '../assets/hero-visual.jpg'

interface HeroSectionProps {
  heroEnterpriseTrialPath: string
  requestDemoPath: string
  navContactSalesPath: string
}

export default function HeroSection({heroEnterpriseTrialPath, requestDemoPath, navContactSalesPath}: HeroSectionProps) {
  return (
    <section id="hero" className="lp-Hero">
      <div className="lp-Hero-visual">
        <canvas className="js-security-hero" />
      </div>
      <div className="lp-Hero-visualFallbackImage">
        <Image src={heroVisual} alt="" width={1280} />
      </div>

      <div className="lp-Container">
        <Hero data-hpc align="center" className="lp-Hero-content">
          <Hero.Label color="green-blue" className="lp-Hero-label">
            GitHub Advanced Security
          </Hero.Label>
          <Hero.Heading size="1" weight="bold" className="lp-Hero-heading">
            Application security <br className="lp-breakWhenWide" /> where found means fixed
          </Hero.Heading>
          <Hero.Description className="lp-Hero-description">Powered by Copilot Autofix.</Hero.Description>
          <Hero.PrimaryAction href={heroEnterpriseTrialPath} className="lp-Hero-ctaButton">
            Start free for 30 days
          </Hero.PrimaryAction>
          <Hero.SecondaryAction href={requestDemoPath} hasArrow={false} className="lp-Hero-ctaButton">
            Request a demo
          </Hero.SecondaryAction>
        </Hero>

        <div className="lp-Hero-logos">
          <LogoSuite className="enterprise-logo-suite" hasDivider={false}>
            <LogoSuite.Heading visuallyHidden>GitHub Security is used by</LogoSuite.Heading>
            <LogoSuite.Logobar marquee marqueeSpeed="slow">
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/telus.svg"
                alt="Telus's logo"
                style={{height: '36px'}}
              />
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/ernst-young.svg"
                alt="Ernst and Young's logo"
                style={{height: '40px'}}
              />
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/mercado-libre.svg"
                alt="Mercado Libre's logo"
                style={{height: '40px'}}
              />
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/shopify.svg"
                alt="Shopify's logo"
                style={{height: '40px'}}
              />
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/linkedin.svg"
                alt="LinkedIn's logo"
                style={{height: '36px'}}
              />
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/3m.svg"
                alt="3M's logo"
                style={{height: '48px'}}
              />
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/kpmg.svg"
                alt="KPMG's logo"
                style={{height: '38px'}}
              />
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/raiffeisen-bank-international.svg"
                alt="Raiffeisen Bank International's logo"
                style={{height: '38px'}}
              />
              <Image
                src="/images/modules/site/enterprise/advanced-security/logos/deutsche-borse.svg"
                alt="Deutsche Börse's logo"
                style={{height: '48px'}}
              />
            </LogoSuite.Logobar>
          </LogoSuite>
        </div>

        <Box className="lp-AnchorNav" style={{height: 0}}>
          <AnchorNav hideUntilSticky>
            <AnchorNav.Link href="#enterprise">Enterprise-ready</AnchorNav.Link>
            <AnchorNav.Link href="#features">Features</AnchorNav.Link>
            <AnchorNav.Link href="#pricing">Pricing</AnchorNav.Link>
            <AnchorNav.Link href="#faq">FAQs</AnchorNav.Link>
            <AnchorNav.Action href={navContactSalesPath}>Contact sales</AnchorNav.Action>
            <AnchorNav.SecondaryAction href={requestDemoPath}>Request a demo</AnchorNav.SecondaryAction>
          </AnchorNav>
        </Box>
      </div>
    </section>
  )
}
