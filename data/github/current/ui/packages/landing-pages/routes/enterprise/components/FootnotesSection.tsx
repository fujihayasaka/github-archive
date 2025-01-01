import {Footnotes, InlineLink} from '@primer/react-brand'

export default function FootnotesSection() {
  return (
    <Footnotes>
      <Footnotes.Item id="footnote-1" href="#footnote-ref-1">
        GitHub, “
        <InlineLink href="https://github.blog/news-insights/research/research-quantifying-github-copilots-impact-on-developer-productivity-and-happiness/">
          Research: quantifying GitHub Copilot’s impact on developer productivity and happiness
        </InlineLink>
        ”, 2022
      </Footnotes.Item>

      <Footnotes.Item id="footnote-2" href="#footnote-ref-2">
        The Total Economic Impact™ Of GitHub Enterprise Cloud and Advanced Security, a commissioned study conducted by
        Forrester Consulting, 2022. Results are for a composite organization based on interviewed customers.
      </Footnotes.Item>
    </Footnotes>
  )
}
