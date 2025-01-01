// FootnoteLink component

const COPY = {
  a11y: 'Jump to footnote',
}

export interface FootnoteLinkProps {
  number: string
}

const defaultProps: Partial<FootnoteLinkProps> = {}

const FootnoteLink: React.FC<FootnoteLinkProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {number} = initializedProps

  return (
    <a id={`footnote-ref-${number}`} href={`#footnote-${number}`} className="lp-FootnoteLink">
      <sup>
        <span className="sr-only">{COPY.a11y}&nbsp;</span>
        {number}
      </sup>
    </a>
  )
}

export default FootnoteLink
