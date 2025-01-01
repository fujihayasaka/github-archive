import {useId} from 'react'
import {clsx} from 'clsx'

import Styles from './AccordionItem.module.css'

export interface AccordionItemProps {
  heading: React.ReactNode | React.ReactNode[]
  content: React.ReactNode | React.ReactNode[]
  isExpanded: boolean
  onToggle: (state: boolean) => void
  className?: string
  isListItem?: boolean
}

const defaultProps: Partial<AccordionItemProps> = {}

const AccordionItem: React.FC<AccordionItemProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {heading, content, isExpanded, onToggle, className, isListItem} = initializedProps

  const id = useId()
  const TermTag = isListItem ? 'dt' : 'div'
  const DescriptionTag = isListItem ? 'dd' : 'div'

  return (
    <div className={clsx(Styles['AccordionItem'], className)} data-open={isExpanded}>
      <TermTag>
        <button
          className={Styles['AccordionItem__heading']}
          aria-expanded={isExpanded}
          aria-controls={id}
          onClick={() => onToggle(!isExpanded)}
        >
          {heading}
        </button>
      </TermTag>
      <DescriptionTag {...(!isExpanded && {'aria-hidden': true})}>
        <div
          id={id}
          className={clsx(Styles['AccordionItem__content'], isExpanded && Styles['AccordionItem__content--expanded'])}
        >
          <div>{content}</div>
        </div>
      </DescriptionTag>
    </div>
  )
}

export default AccordionItem
