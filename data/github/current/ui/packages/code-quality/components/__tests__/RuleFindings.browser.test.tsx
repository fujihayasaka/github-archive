import {render as reactRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getRuleFindingsResponse} from '../../test-utils/mock-data'
import {msw, http, HttpResponse} from '@github-ui/tests/msw'
import type {GetRuleFindingsResponse} from '../../types/get-rule-findings-response'
import {RuleFindings, type RuleFindingsProps} from '../RuleFindings'
import {describe, expect, it} from '@github-ui/tests'

function seedServer({ruleFindings = getRuleFindingsResponse()}: {ruleFindings?: GetRuleFindingsResponse}) {
  msw.use(
    http.get('/:owner/:repo/security/quality/rules/:rule_id/findings', () => {
      return HttpResponse.json(ruleFindings)
    }),
  )
}

const defaultProps: RuleFindingsProps = {
  owner: 'octodemo',
  repo: 'repo1',
  ruleId: 'foo',
  fileCount: 2,
}

const render = (props: Partial<RuleFindingsProps> = {}) => reactRender(<RuleFindings {...defaultProps} {...props} />)

describe('RuleFindings', () => {
  it('Renders the correct number of findings', async () => {
    seedServer({})
    render()

    expect(await screen.findByText('Found 3 findings in 2 files')).toBeInTheDocument()
  })

  it('Correctly pluralizes the number of findings for 1 finding', async () => {
    const ruleFindings = {
      ...getRuleFindingsResponse(),
      findingsCount: 1,
    }

    seedServer({ruleFindings})
    render()

    expect(await screen.findByText('Found 1 finding in 2 files')).toBeInTheDocument()
  })

  it('Correctly pluralizes the number of findings for 0 findings', async () => {
    const ruleFindings = {
      ...getRuleFindingsResponse(),
      findingsCount: 0,
    }

    seedServer({ruleFindings})
    render()

    expect(await screen.findByText('Found 0 findings in 2 files')).toBeInTheDocument()
  })

  it('Renders the rule findings', async () => {
    seedServer({})
    render()

    // Check the first finding
    expect(await screen.findByText('const foo = bar')).toBeInTheDocument()
    expect(await screen.findByText('src/Component1.tsx:1')).toBeInTheDocument()

    // Check the second finding
    expect(await screen.findByText("console.log('Hello World')")).toBeInTheDocument()
    expect(await screen.findByText('src/Component2.tsx:10')).toBeInTheDocument()

    // Check the third finding
    expect(await screen.findByText('const bar = foo')).toBeInTheDocument()
    expect(await screen.findByText('src/SecondComponent.tsx:20')).toBeInTheDocument()
  })

  it('Shows error message when findings cannot be loaded', async () => {
    msw.use(
      http.get('/:owner/:repo/security/quality/rules/:rule_id/findings', () => {
        return HttpResponse.json({}, {status: 500})
      }),
    )

    render()

    expect(await screen.findByText('An error has occurred.')).toBeInTheDocument()
    expect(await screen.findByText('Rule findings data could not be loaded right now.')).toBeInTheDocument()
  })
})
