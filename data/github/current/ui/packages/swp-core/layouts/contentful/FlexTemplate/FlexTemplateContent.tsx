import {isFeatureEnabled} from '@github-ui/feature-flags'

import {ContentfulFlexSection} from '../../../components/contentful/ContentfulFlexSection/ContentfulFlexSection'
import {useFootnotes} from '../../../components/contentful/ContentfulFootnotes/FootnotesContext'
import type {FlexPage} from '../../../schemas/contentful/contentTypes/flexTemplate'
import {FlexTemplateHero} from './FlexTemplateHero'
import {FlexTemplateTrailingSection} from './FlexTemplateTrailingSection/FlexTemplateTrailingSection'

import styles from './FlexTemplate.module.css'

export function FlexTemplateContent({page}: {page: FlexPage}) {
  const {template} = page.fields

  const {sections, ctaBanner, faq, staticFootnotes} = template.fields

  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')
  const footnotesContext = useFootnotes()
  const hasInlineFootnotes = footnotesEnabled && footnotesContext?.footnotes && footnotesContext.footnotes.length > 0
  const hasAnyFootnotes = footnotesEnabled && (hasInlineFootnotes || !!staticFootnotes)
  const hasTrailingSection = ctaBanner || faq || hasAnyFootnotes

  return (
    <>
      <FlexTemplateHero page={page} />

      {sections.map(section => (
        <ContentfulFlexSection key={section.sys.id} component={section} className={styles.section} />
      ))}

      {hasTrailingSection && <FlexTemplateTrailingSection page={page} />}
    </>
  )
}
