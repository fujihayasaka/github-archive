import {useEffect} from 'react'

import {Image, Testimonial} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function TestimonialsSection() {
  useEffect(() => {
    const intro = document.querySelector('.lp-Testimonials')

    if (intro) {
      const observer = new IntersectionObserver(
        entries => {
          const entry = entries[0]
          if (entry?.isIntersecting) {
            intro.classList.add('isVisible')
          } else {
            intro.classList.remove('isVisible')
          }
        },
        {
          root: null, // Use the viewport as the root
          rootMargin: '0px',
          threshold: 0.5, // Trigger when 50% is visible
        },
      )

      observer.observe(intro)

      return () => {
        observer.unobserve(intro)
      }
    }
  }, [])

  return (
    <section id="testimonials" className="lp-Testimonials">
      <div className="fp-Section-container lp-TestimonialsContainer">
        <Image
          className="lp-TestimonialsVisual lp-TestimonialsVisual--1"
          src="/images/modules/site/actions/fp24/testimonial-bg-1.webp"
          loading="lazy"
          width={662}
          alt=""
        />

        <Image
          className="lp-TestimonialsVisual lp-TestimonialsVisual--2"
          src="/images/modules/site/actions/fp24/testimonial-bg-2.webp"
          loading="lazy"
          width={1080}
          alt=""
        />

        <Spacer size="64px" size1012="128px" />

        <Testimonial quoteMarkColor="green" size="large" className="lp-Testimonial fp-gradientBorder">
          <Testimonial.Quote className="lp-TestimonialQuote">
            Actions is an exciting development and unlocks so much potential beyond CI/CD.{' '}
            <span className="lp-TestimonialQuoteDescription">
              It promises to streamline our workflows for a variety of tasks, from deploying our websites to querying
              the GitHub API for custom status reports to standard CI builds.
            </span>
          </Testimonial.Quote>

          <Testimonial.Name position="SciPy maintainer">Ralf Gommers</Testimonial.Name>
        </Testimonial>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
