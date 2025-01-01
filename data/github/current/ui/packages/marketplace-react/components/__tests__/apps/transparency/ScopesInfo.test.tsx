import {ScopesInfo} from '../../../apps/transparency/ScopesInfo'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('ScopesInfo', () => {
  it('Renders scope information text', () => {
    render(<ScopesInfo />)

    expect(screen.getByTestId('scopes-info')).toBeInTheDocument()
    expect(
      screen.getByText(
        /OAuth Apps use scopes to grant access based on your current user permissions. You can view the specific scopes being requested before completing authorization. Scopes requested may change over time and depending on which resources you have access to. GitHub Apps use fixed, granular controls set at installation time./,
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('Learn more about OAuth and GitHub Apps')).toHaveAttribute(
      'href',
      'https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps',
    )
  })
})
