import {Text} from '@primer/react-brand'
import {getFootnoteId} from '../../utils/footnotes'

export interface FootnoteProps {
  number: number
  text: string
  isVisible: boolean
}

const defaultProps: Partial<FootnoteProps> = {}

const Footnote: React.FC<FootnoteProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {number, text, isVisible} = initializedProps

  return (
    <div id={getFootnoteId(number)} className={`Footnote ${isVisible ? 'Footnote--visible' : ''}`}>
      <p>
        <Text weight="light" size="100">
          <sup>{number}</sup>
        </Text>
        <Text weight="light" size="100">
          {/* eslint-disable-next-line react/no-danger */}
          <span dangerouslySetInnerHTML={{__html: text}} />
        </Text>
      </p>
    </div>
  )
}

export default Footnote
