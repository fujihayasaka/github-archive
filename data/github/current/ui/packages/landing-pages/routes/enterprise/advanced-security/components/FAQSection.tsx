import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import resolveResponse from 'contentful-resolve-response'
import {useEffect} from 'react'

import {toContainerPage, toEntryCollection} from '../../../../lib/types/contentful'
import {toPayload} from '../../../../lib/types/payload'
import {toAdvancedSecurityTemplate, type AdvancedSecurityTemplate} from '../../utils/template'

interface FAQSectionProps {
  payload: unknown
}

export default function FAQSection({payload}: FAQSectionProps) {
  let template: AdvancedSecurityTemplate | undefined

  try {
    const {contentfulRawJsonResponse} = toPayload(payload)
    const page = toContainerPage(toEntryCollection(resolveResponse(contentfulRawJsonResponse)).at(0))

    template = toAdvancedSecurityTemplate(page.fields.template)
  } catch {
    // We don't break the page if we can't parse the Contentful data.
  }

  useEffect(() => {
    /**
     * If the template is undefined, it means we haven't be able to parse the Contentful data. Typically,
     * this is because the data does not match the expected schema. In these instances, we throw an error
     * asynchronously so it is reported to Sentry but don't unmount the component from an uncaught error.
     *
     * Since the template is undefined, we render the page without the Contentful data (e.g., the FAQ section
     * will be empty).
     */
    if (template === undefined) {
      const timeout = window.setTimeout(() => {
        throw new Error(`We were unable to parse the Contentful data for the Advanced Security landing page.`)
      })

      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [template])

  return (
    <section id="faq" className="lp-Section--faqs">
      <div className="lp-Container">
        <div
          className="lp-Spacer"
          style={{'--lp-space': '72px', '--lp-space-xl': '128px'} as React.CSSProperties}
          aria-hidden
        />

        {template !== undefined && <ContentfulFaqGroup component={template.fields.sections[0].fields.components[0]} />}

        <div
          className="lp-Spacer"
          style={{'--lp-space': '72px', '--lp-space-xl': '128px'} as React.CSSProperties}
          aria-hidden
        />
      </div>
    </section>
  )
}
