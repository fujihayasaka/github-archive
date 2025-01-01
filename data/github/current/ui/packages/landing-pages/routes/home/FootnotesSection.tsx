import {Footnotes, Section} from '@primer/react-brand'

import {COPY} from './FootnotesSection.data'

export default function FootnotesSection() {
  return (
    <Section id="footnotes" className="p-responsive py-0">
      <Footnotes>
        {COPY.map((item, index) => (
          <Footnotes.Item
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={index}
            id={`footnote-${index + 1}`}
            href={`#footnote-ref-${index + 1}`}
            className="lp-Footnotes-item"
          >
            {/* eslint-disable-next-line react/no-danger */}
            <span dangerouslySetInnerHTML={{__html: item.footnote}} />
          </Footnotes.Item>
        ))}
      </Footnotes>
    </Section>
  )
}
