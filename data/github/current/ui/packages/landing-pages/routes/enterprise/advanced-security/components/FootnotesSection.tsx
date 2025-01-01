import {Footnotes} from '@primer/react-brand'

export default function FootnotesSection() {
  return (
    <section id="footnotes" className="lp-Section--footnotes">
      <div className="lp-Container">
        <Footnotes>
          <Footnotes.Item>
            Overall, the median time for developers to use Copilot Autofix to automatically commit the fix for a PR-time
            alert was 28 minutes, compared to 1.5 hours to resolve the same alerts manually (3x faster). For SQL
            injection vulnerabilities: 18 minutes compared to 3.7 hours (12x faster). Based on new code scanning alerts
            found by CodeQL in pull requests (PRs) on repositories with GitHub Advanced Security enabled. These are
            examples; your results will vary.
          </Footnotes.Item>

          <Footnotes.Item>
            A Comparative Study of Software Secrets Reporting by Secret Detection Tools, Setu Kumar Basak et al., North
            Carolina State University, 2023
          </Footnotes.Item>
        </Footnotes>
      </div>
    </section>
  )
}
