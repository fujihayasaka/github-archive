import {AnchorNav} from '@primer/react-brand'
import type {PrimerComponentAnchorNav} from '../../../schemas/contentful/contentTypes/primerComponentAnchorNav'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'

export type ContentfulAnchorNavProps = {
  component: PrimerComponentAnchorNav

  /**
   * The props below do not have a corresponding field in Contentful:
   */
  className?: string
}

const ANALYTICS_CONTEXT = 'sticky'
const ANALYTICS_LOCATION = 'anchor_nav'

export const ContentfulAnchorNav = ({component}: ContentfulAnchorNavProps) => {
  const {links, action} = component.fields
  return (
    <AnchorNav>
      {links.map(item => (
        <AnchorNav.Link
          key={item.sys.id}
          href={`#${item.fields.href}`}
          aria-label={item.fields.ariaLabel ?? item.fields.text}
          data-testid={`${item.sys.id}-anchor-link`}
          {...getAnalyticsEvent({
            action: item.fields.text,
            tag: 'link',
            context: ANALYTICS_CONTEXT,
            location: ANALYTICS_LOCATION,
          })}
        >
          {item.fields.text}
        </AnchorNav.Link>
      ))}

      {action && (
        <AnchorNav.Action
          href={action.fields.href}
          {...getAnalyticsEvent({
            action: action.fields.text,
            tag: 'button',
            context: ANALYTICS_CONTEXT,
            location: ANALYTICS_LOCATION,
          })}
        >
          {action.fields.text}
        </AnchorNav.Action>
      )}
    </AnchorNav>
  )
}
