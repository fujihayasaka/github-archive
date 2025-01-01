import {render, screen} from '@testing-library/react'
import {createRef} from 'react'

import {
  DefinitionsLimitBanner,
  DefinitionUsageBanner,
  isDefinitionsLimitReached,
  ServerErrorFormBanner,
} from '../Banners'

describe('Banners', () => {
  describe('isDefinitionsLimitReached', () => {
    it('returns false when definitions count is below the limit', () => {
      expect(isDefinitionsLimitReached(0)).toBe(false)
      expect(isDefinitionsLimitReached(50)).toBe(false)
      expect(isDefinitionsLimitReached(99)).toBe(false)
    })

    it('returns true when definitions count equals or excess the limit', () => {
      expect(isDefinitionsLimitReached(100)).toBe(true)
      expect(isDefinitionsLimitReached(101)).toBe(true)
      expect(isDefinitionsLimitReached(150)).toBe(true)
    })
  })

  describe('DefinitionsLimitBanner', () => {
    it('renders with correct variant', () => {
      render(<DefinitionsLimitBanner />)

      const banner = screen.getByTestId('definitions-limit-banner')
      expect(banner).toHaveTextContent('The limit of 100 definitions is reached. You cannot add more.')
      expect(banner).toHaveAttribute('data-variant', 'info')
    })
  })

  describe('ServerErrorFormBanner', () => {
    it('renders children as description', () => {
      render(<ServerErrorFormBanner>Server error occurred.</ServerErrorFormBanner>)

      const banner = screen.getByTestId('server-error-banner')
      expect(banner).toHaveTextContent('Server error occurred.')
      expect(banner).toHaveAttribute('data-variant', 'critical')
    })

    it('forwards ref correctly', () => {
      const ref = createRef<HTMLDivElement>()
      render(<ServerErrorFormBanner ref={ref} />)

      const banner = screen.getByTestId('server-error-banner')
      expect(banner).toBeInTheDocument()
      expect(ref.current).toBe(banner)
    })
  })

  describe('DefinitionUsageBanner', () => {
    it('renders correctly when there are usages', () => {
      render(<DefinitionUsageBanner name="environment" repoCount={3} />)

      const banner = screen.getByTestId('usage-banner')
      expect(banner).toHaveTextContent('The environment property is referenced by 3 repositories.')
      expect(banner).toHaveAttribute('data-variant', 'warning')
    })

    it('renders correctly when there are no usages', () => {
      render(<DefinitionUsageBanner name="environment" repoCount={0} />)

      const banner = screen.getByTestId('usage-banner')
      expect(banner).toContainHTML('No usages of the <strong>environment</strong> property found.')
      expect(banner).toHaveAttribute('data-variant', 'info')
    })
  })
})
