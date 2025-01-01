import type {FootnoteMethods} from '../../../hooks/useFootnotes'
import {getFootnoteId} from '../../../utils/footnotes'

export interface FootnoteToggleProps {
  number: number
  isExpanded: boolean
  onClick: FootnoteMethods['onFootnoteClick']
  onEnter: FootnoteMethods['onFootnoteEnter']
  onKeyDown: FootnoteMethods['onFootnoteKeyDown']
}

const defaultProps: Partial<FootnoteToggleProps> = {}

const FootnoteToggle: React.FC<FootnoteToggleProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {number, isExpanded, onClick, onEnter, onKeyDown} = initializedProps

  return (
    // TODO: Review accessibility
    <button
      className="Footnote-toggle"
      onClick={event => onClick(number, event)}
      onPointerEnter={event => onEnter(number, event)}
      onKeyDown={event => onKeyDown(number, event)}
      aria-expanded={isExpanded}
      aria-controls={getFootnoteId(number)}
    >
      <sup>{number}</sup>
    </button>
  )
}

export default FootnoteToggle
