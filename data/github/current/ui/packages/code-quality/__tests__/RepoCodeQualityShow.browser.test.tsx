import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {msw, http, HttpResponse} from '@github-ui/tests/msw'
import {getRepoCodeQualityShowRoutePayload, getRuleFindingsResponse} from '../test-utils/mock-data'
import {codeQualityApp} from '../code-quality'
import type {RepoCodeQualityShowResponse} from '../routes/repo-code-quality-show-route'
import type {GetRuleFindingsResponse} from '../types/get-rule-findings-response'
import {describe, expect, it} from '@github-ui/tests'

function seedServer({
  mainQuery,
  ruleFindings = getRuleFindingsResponse(),
}: {
  mainQuery: RepoCodeQualityShowResponse
  ruleFindings?: GetRuleFindingsResponse
}) {
  msw.use(
    http.get('/:owner/:repo/security/quality/rules/:rule_id', () => {
      return HttpResponse.json({
        payload: {
          repoCodeQualityShowRoute: mainQuery,
        },
      })
    }),
  )

  msw.use(
    http.get('/:owner/:repo/security/quality/rules/:rule_id/findings', () => {
      return HttpResponse.json(ruleFindings)
    }),
  )
}

describe('RepoCodeQualityShow', () => {
  it('Renders the RepoCodeQualityShow component', async () => {
    const mainQuery = getRepoCodeQualityShowRoutePayload()

    seedServer({mainQuery})
    render(codeQualityApp, '/:owner/:repo/security/quality/rules/foo', {
      appPayload: {},
    })

    // Check title
    const heading = await screen.findByRole('heading', {name: 'Inefficient use of ContainsKey', level: 1})
    expect(heading).toBeInTheDocument()

    // Check breadcrumb code quality link
    const codeQualityLink = await screen.findByRole('link', {name: 'Code quality'})
    expect(codeQualityLink).toBeInTheDocument()
    expect(codeQualityLink).toHaveAttribute('href', '/octodemo/repo1/security/quality')

    // Check for rule name in breadcrumb
    const ruleBreadcrumb = await screen.findByText('Inefficient use of ContainsKey', {selector: 'a'})
    expect(ruleBreadcrumb).toBeInTheDocument()
    expect(ruleBreadcrumb).toHaveAttribute('aria-current', 'page')

    // Check the last scan
    expect(await screen.findByText(/Last scan:/)).toBeInTheDocument()

    // Check the description
    expect(await screen.findByText(mainQuery.ruleDescription)).toBeInTheDocument()

    // Check the sidebar
    expect(await screen.findByText('Category')).toBeInTheDocument()
    expect(await screen.findByText('Maintainability')).toBeInTheDocument()
    expect(await screen.findByText('Severity')).toBeInTheDocument()
    expect(await screen.findByText('Warning')).toBeInTheDocument()
  })

  it('Renders the rule findings', async () => {
    const mainQuery = getRepoCodeQualityShowRoutePayload()

    seedServer({mainQuery})
    render(codeQualityApp, '/:owner/:repo/security/quality/rules/foo', {
      appPayload: {},
    })

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

  it('Renders the blankslate when there are no findings', async () => {
    const mainQuery = {...getRepoCodeQualityShowRoutePayload(), fileCount: 0}

    seedServer({mainQuery})
    render(codeQualityApp, '/:owner/:repo/security/quality/rules/foo', {
      appPayload: {},
    })

    expect(await screen.findByText('Finding is no longer available!')).toBeInTheDocument()
  })
})
