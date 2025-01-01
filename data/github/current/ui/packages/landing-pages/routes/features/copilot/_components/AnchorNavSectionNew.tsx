import {AnchorNav, Box} from '@primer/react-brand'
import {analyticsEvent} from '../../../../lib/analytics'

interface AnchorNavSectionNewProps {
  copilotPlansPath: string
}

export default function AnchorNavSectionNew({copilotPlansPath}: AnchorNavSectionNewProps) {
  return (
    <Box style={{height: 0}}>
      <AnchorNav hideUntilSticky>
        <AnchorNav.Link
          href="#pricing"
          {...analyticsEvent({action: 'pricing', tag: 'link', context: 'sticky', location: 'subnav'})}
        >
          Pricing
        </AnchorNav.Link>
        <AnchorNav.Link
          href="#features"
          {...analyticsEvent({action: 'features', tag: 'link', context: 'sticky', location: 'subnav'})}
        >
          Features
        </AnchorNav.Link>
        <AnchorNav.Link
          href="#resources"
          {...analyticsEvent({action: 'resources', tag: 'link', context: 'sticky', location: 'subnav'})}
        >
          Resources
        </AnchorNav.Link>
        <AnchorNav.Link
          href="#faq"
          {...analyticsEvent({action: 'faqs', tag: 'link', context: 'sticky', location: 'subnav'})}
        >
          FAQs
        </AnchorNav.Link>
        <AnchorNav.Action
          href={copilotPlansPath}
          {...analyticsEvent({
            action: 'get_started',
            tag: 'button',
            context: 'sticky',
            location: 'subnav',
          })}
        >
          Get started with Copilot
        </AnchorNav.Action>
        <AnchorNav.SecondaryAction href="#" hidden />
      </AnchorNav>
    </Box>
  )
}
