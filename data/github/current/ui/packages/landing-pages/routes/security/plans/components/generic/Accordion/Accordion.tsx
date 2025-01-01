import AccordionItem from './AccordionItem/AccordionItem'
import type {AccordionItemProps} from './AccordionItem/AccordionItem'

import Styles from './Accordion.module.css'

export interface AccordionProps {
  items: Array<Omit<AccordionItemProps, 'onToggle' | 'className'>>
  onItemToggle: (index: number, state: boolean) => void
  itemClassName?: string
}

const defaultProps: Partial<AccordionProps> = {}

const Accordion: React.FC<AccordionProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {items, onItemToggle, itemClassName} = initializedProps

  return (
    <dl className={Styles['Accordion']}>
      {items.map((item, index) => (
        <AccordionItem
          // eslint-disable-next-line @eslint-react/no-array-index-key
          key={`accordionItem_${index}`}
          {...item}
          onToggle={state => onItemToggle(index, state)}
          className={itemClassName}
          isListItem
        />
      ))}
    </dl>
  )
}

export default Accordion
