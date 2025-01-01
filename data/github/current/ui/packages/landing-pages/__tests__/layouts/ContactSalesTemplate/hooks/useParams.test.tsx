import {render, screen} from '@testing-library/react'

import {useParams} from '../../../../layouts/ContactSalesTemplate/hooks/useParams'

function visit(url: string) {
  Object.defineProperty(window, 'location', {
    value: {
      href: url,
      search: new URL(url, window.location.href).search,
    },
    writable: true,
  })
}

const TestWrapper = () => {
  const params = useParams()

  return (
    <>
      {Object.entries(params).map(([key, value]) => (
        <p key={key}>
          {key}:{value ?? 'undefined'}
        </p>
      ))}
    </>
  )
}

describe('useParams', () => {
  it('returns the default values if no query params are present', async () => {
    visit('http://github.localhost/enterprise/contact')

    render(<TestWrapper />)

    await expect(screen.findByText('ref_cta:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('ref_loc:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('ref_page:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_campaign:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_content:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_medium:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_source:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_term:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('variant:control')).resolves.toBeInTheDocument()
  })

  it('parses the parameters correctly', async () => {
    visit('http://github.localhost/enterprise/contact?utm_source=github_support_portal&utm_medium=homepage_cta')

    render(<TestWrapper />)

    await expect(screen.findByText('ref_cta:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('ref_loc:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('ref_page:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_campaign:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_content:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_medium:homepage_cta')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_source:github_support_portal')).resolves.toBeInTheDocument()
    await expect(screen.findByText('utm_term:undefined')).resolves.toBeInTheDocument()
    await expect(screen.findByText('variant:control')).resolves.toBeInTheDocument()
  })
})
