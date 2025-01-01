import {FAQ as PrimerFaq, FAQGroup as PrimerFaqGroup} from '@primer/react-brand'

import Styles from './Faq.module.css'

export interface FaqItem {
  question: string
  answer: string[]
}

export interface FaqGroup {
  title: string
  items: FaqItem[]
}

export interface FaqProps {
  title: string
  items: FaqGroup[]
}

const defaultProps: Partial<FaqProps> = {}

const Faq: React.FC<FaqProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {title, items} = initializedProps

  return (
    <section id="faq" className={Styles['Faq']}>
      <PrimerFaqGroup>
        <PrimerFaqGroup.Heading as="h3" className={Styles['Faq__title']}>
          {title}
        </PrimerFaqGroup.Heading>

        {items.map((itemGroup, groupIndex) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <PrimerFaq key={`group_${groupIndex}`}>
            <PrimerFaq.Heading as="h3">{itemGroup.title}</PrimerFaq.Heading>
            {itemGroup.items.map((item, itemIndex) => (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <PrimerFaq.Item key={`item_${itemIndex}`}>
                <PrimerFaq.Question as="h4" className={Styles['Faq__question']}>
                  {item.question}
                </PrimerFaq.Question>
                <PrimerFaq.Answer>
                  {item.answer.map((answer, i) => (
                    // eslint-disable-next-line react/no-danger, @eslint-react/no-array-index-key
                    <p key={`item_answer_${i}`} dangerouslySetInnerHTML={{__html: answer}} />
                  ))}
                </PrimerFaq.Answer>
              </PrimerFaq.Item>
            ))}
          </PrimerFaq>
        ))}
      </PrimerFaqGroup>
    </section>
  )
}

export default Faq
