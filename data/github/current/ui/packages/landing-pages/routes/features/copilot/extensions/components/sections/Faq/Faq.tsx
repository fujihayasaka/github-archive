import {FAQ as PrimerFaq} from '@primer/react-brand'

import {COPY} from '../../../Index.data'
import {Spacer} from '../../../../../components/Spacer'

interface FaqProps {}

const defaultProps: Partial<FaqProps> = {}

const Faq: React.FC<FaqProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  return (
    <section id="faq">
      <div className="fp-Section-container">
        <Spacer size="96px" size768="128px" />

        <PrimerFaq className="lp-Faq">
          <PrimerFaq.Heading as="h2">{COPY.faq.title}</PrimerFaq.Heading>
          {COPY.faq.items.map((item, index) => (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <PrimerFaq.Item key={`item_${index}`}>
              <PrimerFaq.Question as="h3">{item.question}</PrimerFaq.Question>
              <PrimerFaq.Answer>
                {item.answer.map((answer, i) => (
                  // eslint-disable-next-line react/no-danger, @eslint-react/no-array-index-key
                  <p key={`item_answer_${i}`} dangerouslySetInnerHTML={{__html: answer}} />
                ))}
              </PrimerFaq.Answer>
            </PrimerFaq.Item>
          ))}
        </PrimerFaq>

        <Spacer size="96px" size768="128px" />
      </div>
    </section>
  )
}

export default Faq
