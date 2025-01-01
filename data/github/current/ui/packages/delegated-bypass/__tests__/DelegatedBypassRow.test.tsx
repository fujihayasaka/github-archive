import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DelegatedBypassRow} from '../components/DelegatedBypassRow'
import {
  exampleRequest,
  baseExemptionUrl,
  approvedRequest,
  deniedRequest,
  completedRequest,
  expiredRequest,
  cancelledRequest,
  requestWithDismissedResponse,
} from './helpers'
import type {SourceType} from '../delegated-bypass-types'

describe('DelegatedBypassRow', () => {
  it('renders a bypass exemption request', () => {
    render(
      <DelegatedBypassRow
        exemptionRequest={exampleRequest}
        baseExemptionUrl={baseExemptionUrl}
        sourceType="repository"
      />,
    )

    expect(screen.getByText('Bypass "ruleset1" and 1 more ruleset')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Bypass "ruleset1" and 1 more ruleset'})).toHaveAttribute(
      'href',
      `${baseExemptionUrl}${exampleRequest.number}`,
    )
    const localizedDate = new Date(exampleRequest.updatedAt).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    })
    expect(screen.getByText(`${localizedDate}`)).toBeInTheDocument()
    expect(screen.queryByRole('link', {name: exampleRequest.repoName})).not.toBeInTheDocument()
  })

  const sourceTypes: SourceType[] = ['organization', 'enterprise']
  it.each(sourceTypes)('renders an exemption request with repo links for orgs and enterprises', source => {
    render(
      <DelegatedBypassRow exemptionRequest={exampleRequest} baseExemptionUrl={baseExemptionUrl} sourceType={source} />,
    )
    expect(screen.getByText('Bypass "ruleset1" and 1 more ruleset')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: exampleRequest.repoName})).toHaveAttribute('href', exampleRequest.repoUrl)
  })

  it('renders an approved exemption request', () => {
    render(
      <DelegatedBypassRow
        exemptionRequest={approvedRequest}
        baseExemptionUrl={baseExemptionUrl}
        sourceType="repository"
      />,
    )

    expect(screen.getByRole('link', {name: 'Bypass "ruleset1" and 1 more ruleset'})).toHaveAttribute(
      'href',
      `${baseExemptionUrl}${approvedRequest.number}`,
    )
    expect(screen.getByText('was approved by')).toBeInTheDocument()
  })

  it('renders a denied bypass exemption request', () => {
    render(
      <DelegatedBypassRow
        exemptionRequest={deniedRequest}
        baseExemptionUrl={baseExemptionUrl}
        sourceType="repository"
      />,
    )

    expect(screen.getByRole('link', {name: 'Bypass "ruleset1" and 1 more ruleset'})).toHaveAttribute(
      'href',
      `${baseExemptionUrl}${deniedRequest.number}`,
    )
    expect(screen.getByText('was denied by')).toBeInTheDocument()
  })

  it('renders a completed bypass exemption request', () => {
    render(
      <DelegatedBypassRow
        exemptionRequest={completedRequest}
        baseExemptionUrl={baseExemptionUrl}
        sourceType="repository"
      />,
    )

    expect(screen.getByRole('link', {name: 'Bypass "ruleset1" and 1 more ruleset'})).toHaveAttribute(
      'href',
      `${baseExemptionUrl}${completedRequest.number}`,
    )
    expect(screen.getByText('was completed')).toBeInTheDocument()
  })

  it('renders an expired bypass exemption request', () => {
    render(
      <DelegatedBypassRow
        exemptionRequest={expiredRequest}
        baseExemptionUrl={baseExemptionUrl}
        sourceType="repository"
      />,
    )

    expect(screen.getByRole('link', {name: 'Bypass "ruleset1" and 1 more ruleset'})).toHaveAttribute(
      'href',
      `${baseExemptionUrl}${expiredRequest.number}`,
    )
    expect(screen.getByText('expired')).toBeInTheDocument()
  })

  it('renders a cancelled bypass exemption request', () => {
    render(
      <DelegatedBypassRow
        exemptionRequest={cancelledRequest}
        baseExemptionUrl={baseExemptionUrl}
        sourceType="repository"
      />,
    )

    expect(screen.getByRole('link', {name: 'Bypass "ruleset1" and 1 more ruleset'})).toHaveAttribute(
      'href',
      `${baseExemptionUrl}${cancelledRequest.number}`,
    )
    expect(screen.getByText('was cancelled')).toBeInTheDocument()
  })

  it('renders a bypass exemption request with a dismissed response', () => {
    render(
      <DelegatedBypassRow
        exemptionRequest={requestWithDismissedResponse}
        baseExemptionUrl={baseExemptionUrl}
        sourceType="repository"
      />,
    )

    expect(screen.getByRole('link', {name: 'Bypass "ruleset1" and 1 more ruleset'})).toHaveAttribute(
      'href',
      `${baseExemptionUrl}${requestWithDismissedResponse.number}`,
    )
    const localizedDate = new Date(exampleRequest.updatedAt).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    })
    expect(screen.getByText(`${localizedDate}`)).toBeInTheDocument()
  })
})
