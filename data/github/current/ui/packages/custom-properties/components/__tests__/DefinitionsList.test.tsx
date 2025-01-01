import type {PropertyDefinition} from '@github-ui/custom-properties-types'
import {screen} from '@testing-library/react'

import {albumDefinition} from '../../test-utils/mock-data'
import {
  renderPropertyDefinitionsComponent,
  renderPropertyDefinitionsComponentAtEnterpriseLevel,
} from '../../test-utils/Render'
import {DefinitionsList} from '../DefinitionsList'

const businessDefinition: PropertyDefinition = {
  ...albumDefinition,
  source: {
    type: 'business',
    name: 'Acme, Inc.',
    slug: 'acme-inc',
    avatarUrl: 'avatar.com',
  },
}

describe('DefinitionsList', () => {
  describe('org view', () => {
    it('displays managed by link for business managed property', () => {
      renderPropertyDefinitionsComponent(<DefinitionsList definitions={[businessDefinition]} totalCount={1} />)
      const link = screen.getByRole('link', {name: 'Acme, Inc.'})
      expect(link.getAttribute('href')).toEqual('/enterprises/acme-inc')
    })
    it('does not display managed by link for non-business managed property', () => {
      renderPropertyDefinitionsComponent(<DefinitionsList definitions={[albumDefinition]} totalCount={1} />)
      expect(screen.queryByRole('link', {name: 'Acme, Inc.'})).not.toBeInTheDocument()
    })
  })

  describe('business view', () => {
    it('displays managed by link for business managed property', () => {
      renderPropertyDefinitionsComponentAtEnterpriseLevel(
        <DefinitionsList definitions={[businessDefinition]} totalCount={1} />,
      )
      const link = screen.getByRole('link', {name: 'Acme, Inc.'})
      expect(link.getAttribute('href')).toEqual('/enterprises/acme-inc')
    })

    it('displays managed by link for org managed property', () => {
      const orgDefinition: PropertyDefinition = {
        ...albumDefinition,
        source: {
          type: 'org',
          name: 'GitHub Org',
          slug: 'github-org',
          avatarUrl: 'avatar.com',
        },
      }
      renderPropertyDefinitionsComponentAtEnterpriseLevel(
        <DefinitionsList definitions={[orgDefinition]} totalCount={1} />,
      )
      const link = screen.getByRole('link', {name: 'GitHub Org'})
      expect(link.getAttribute('href')).toEqual('/github-org')
    })
  })
})
