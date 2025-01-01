import {useEffect} from 'react'
import resolveResponse from 'contentful-resolve-response'

import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import {toContainerPage, toEntryCollection} from '../../../lib/types/contentful'
import {toPayload} from '../../../lib/types/payload'

import {toEnterpriseTemplate, type EnterpriseTemplate} from '../utils/template'

export default function FAQSection() {
  const payload = useRoutePayload<unknown>()

  let template: EnterpriseTemplate | undefined

  try {
    const {contentfulRawJsonResponse} = toPayload(payload)
    const page = toContainerPage(toEntryCollection(resolveResponse(contentfulRawJsonResponse)).at(0))

    template = toEnterpriseTemplate(page.fields.template)
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
        throw new Error(`We were unable to parse the Contentful data for the Enterprise landing page.`)
      })

      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [template])

  if (template !== undefined) {
    return <ContentfulFaqGroup component={template.fields.sections[0].fields.components[0]} />
  }

  return <></>
}
