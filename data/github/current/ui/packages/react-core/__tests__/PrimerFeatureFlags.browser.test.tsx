import {mockClientEnv} from '@github-ui/client-env/mock'
import {expect, it, vi} from '@github-ui/tests'
import {FeatureFlags} from '@primer/react/experimental'
import {render, screen} from '@testing-library/react'

import {PrimerFeatureFlags} from '../PrimerFeatureFlags'

// Note: there is not currently an exported member from @primer/react that allows us to test if a flag has been passed
// along through the FeatureFlags context provider. As a result, we mock the component and assert on the flags that are
// being passed along in order to test the logic of PrimerFeatureFlags
vi.mock('@primer/react/experimental', async () => {
  const implementation = await vi.importActual('@primer/react/experimental')
  return {
    ...implementation,
    FeatureFlags: vi.fn().mockImplementation(implementation.FeatureFlags as typeof FeatureFlags),
  }
})

it('renders children', () => {
  render(
    <PrimerFeatureFlags>
      <span>test child</span>
    </PrimerFeatureFlags>,
  )
  expect(screen.getByText('test child')).toBeInTheDocument()
})

it('forwards primer_react_* flags to FeatureFlags in @primer/react', () => {
  mockClientEnv({
    featureFlags: ['primer_react_test'],
  })

  render(
    <PrimerFeatureFlags>
      <span>test child</span>
    </PrimerFeatureFlags>,
  )

  expect(FeatureFlags).toHaveBeenLastCalledWith(
    expect.objectContaining({
      flags: {
        primer_react_test: true,
      },
    }),
    {},
  )
})

it('does not forward non-primer_react_* flags to FeatureFlags in @primer/react', () => {
  mockClientEnv({
    featureFlags: ['example_github_ui_flag'],
  })

  render(
    <PrimerFeatureFlags>
      <span>test child</span>
    </PrimerFeatureFlags>,
  )

  expect(FeatureFlags).toHaveBeenLastCalledWith(
    expect.objectContaining({
      flags: {},
    }),
    {},
  )
})
