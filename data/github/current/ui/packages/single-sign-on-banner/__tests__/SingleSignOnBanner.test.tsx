import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {SingleSignOnBanner} from '../SingleSignOnBanner'

test('Does not render when no protectedOrgs', () => {
  render(<SingleSignOnBanner />)

  expect(screen.queryByRole('region', {name: 'Single sign-on information'})).not.toBeInTheDocument()
})

test('Does not render when empty protectedOrgs', () => {
  render(<SingleSignOnBanner protectedOrgs={[]} />)

  expect(screen.queryByRole('region', {name: 'Single sign-on information'})).not.toBeInTheDocument()
})

test('Renders with one org', () => {
  render(<SingleSignOnBanner protectedOrgs={['github']} />)

  const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
  expect(ssoBanner.textContent).toContain('Single sign-on to see results in the github organization.')
})

test('Renders with two orgs', () => {
  render(<SingleSignOnBanner protectedOrgs={['github', 'acme']} />)

  const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
  expect(ssoBanner.textContent).toContain('Single sign-on to see results in the github and acme organizations.')
})

test('Renders with three orgs', () => {
  render(<SingleSignOnBanner protectedOrgs={['github', 'acme', 'groovy']} />)

  const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
  expect(ssoBanner.textContent).toContain(
    'Single sign-on to see results in the github, acme, and groovy organizations.',
  )
})

test('Renders with four orgs', () => {
  render(<SingleSignOnBanner protectedOrgs={['github', 'acme', 'groovy', 'monalisa']} />)

  const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
  expect(ssoBanner.textContent).toContain(
    'Single sign-on to see results in github, acme, groovy and 1 other organization.',
  )
})

test('Renders with five orgs', () => {
  render(<SingleSignOnBanner protectedOrgs={['github', 'acme', 'groovy', 'monalisa', 'copilot']} />)

  const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
  expect(ssoBanner.textContent).toContain(
    'Single sign-on to see results in github, acme, groovy and 2 other organizations.',
  )
})

describe('maxVisibleOrgNames', () => {
  test('Renders with max visible set to 0', () => {
    render(<SingleSignOnBanner protectedOrgs={['github', 'acme', 'monalisa']} maxVisibleOrgNames={0} />)

    const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
    expect(ssoBanner.textContent).toContain('Single sign-on to see results in 3 other organizations.')
  })

  test('Renders one org even if max visible is 0', () => {
    render(<SingleSignOnBanner protectedOrgs={['github']} maxVisibleOrgNames={0} />)

    const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
    expect(ssoBanner.textContent).toContain('Single sign-on to see results in the github organization.')
  })

  test('Renders with max visible org names fewer than number of orgs', () => {
    render(<SingleSignOnBanner protectedOrgs={['github', 'acme', 'groovy', 'monalisa']} maxVisibleOrgNames={3} />)

    const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
    expect(ssoBanner.textContent).toContain(
      'Single sign-on to see results in github, acme, groovy and 1 other organization.',
    )
  })

  test('Renders with max visible org names equal to number of orgs', () => {
    render(<SingleSignOnBanner protectedOrgs={['github', 'acme', 'groovy']} maxVisibleOrgNames={3} />)

    const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
    expect(ssoBanner.textContent).toContain(
      'Single sign-on to see results in the github, acme, and groovy organizations.',
    )
  })

  test('Renders with max visible org names greater than number of orgs', () => {
    render(<SingleSignOnBanner protectedOrgs={['github', 'acme']} maxVisibleOrgNames={3} />)

    const ssoBanner = screen.getByRole('region', {name: 'Single sign-on information'})
    expect(ssoBanner.textContent).toContain('Single sign-on to see results in the github and acme organizations.')
  })
})
