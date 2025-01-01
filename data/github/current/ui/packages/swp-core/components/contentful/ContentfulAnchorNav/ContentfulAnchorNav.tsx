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

export const ContentfulAnchorNav = ({component, className = 'py-3'}: ContentfulAnchorNavProps) => {
  const {links, action} = component.fields
  return (
    <AnchorNav className={className}>
      {links.map(item => (
        <AnchorNav.Link
          key={item.fields.id}
          href={`#${item.fields.id}`}
          aria-label={`Jump to ${item.fields.text}`}
          data-testid={`${item.fields.id}-anchor-link`}
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
