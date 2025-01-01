import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {PlusIcon} from '@primer/octicons-react'
import {Heading, Link, Text} from '@primer/react-brand'
import {useId} from 'react'

interface AccordionItem {
  title: string
  description: string
  link: {
    url: string
    label: string
  }
  visual: {
    url: string
    alt: string
  }
}

export interface AccordionProps {
  items: AccordionItem[]
  currentIndex: number
  onChange: (index: number) => void
  analyticsId?: string
}

const defaultProps: Partial<AccordionProps> = {}

const Accordion: React.FC<AccordionProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {items, currentIndex, onChange, analyticsId} = initializedProps

  const id = useId()

  return (
    <dl className="lp-Accordion">
      {items.map((item, index) => {
        const itemId = `${id}_${index}`
        const isExpanded = currentIndex === index

        return (
          <div
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={`accordionItem_${index}`}
            className="lp-AccordionItem"
            data-open={isExpanded}
          >
            <dt>
              <button
                className="lp-AccordionDisclosure"
                aria-expanded={isExpanded}
                aria-controls={itemId}
                onClick={() => onChange(index)}
              >
                <div className="lp-AccordionItem-summary">
                  <Heading className="lp-AccordionItem-heading" as="h3" size="6">
                    {item.title}
                  </Heading>

                  <PlusIcon />
                </div>
              </button>
            </dt>
            <dd {...(!isExpanded && {'aria-hidden': true})}>
              <div
                id={itemId}
                className={`lp-AccordionDisclosure-content ${
                  isExpanded ? 'lp-AccordionDisclosure-content--expanded' : ''
                }`}
              >
                <div className="lp-AccordionContent">
                  <Text size="300" as="p">
                    {/* eslint-disable-next-line react/no-danger */}
                    <span dangerouslySetInnerHTML={{__html: item.description}} />
                  </Text>
                  {/* Accessibility: Reads image alt text as part of the accordion expansion */}
                  <span className="sr-only">{item.visual.alt}</span>
                  <Link
                    variant="accent"
                    href={item.link.url}
                    {...(!isExpanded && {tabIndex: -1})}
                    {...getAnalyticsEvent({
                      action: item.link.label,
                      tag: 'link',
                      context: 'accordion',
                      location: analyticsId,
                    })}
                  >
                    <Text weight="normal" size="300">
                      {item.link.label}
                    </Text>
                  </Link>
                </div>
              </div>
            </dd>
          </div>
        )
      })}
    </dl>
  )
}

export default Accordion
