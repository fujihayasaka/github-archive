import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {OrgConflictsDialog} from '../OrgConflictsDialog'

describe('OrgConflictsDialog', () => {
  it('renders too many orgs message if total usages is more than displayed list', async () => {
    // The CSS parser for jsdom does not support some of the styling syntax for Banner and will fail
    // with an error containing the message below.
    // Tracking issue: https://github.com/github/primer/issues/3882
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })

    render(
      <OrgConflictsDialog
        displayMessage="This property cannot be created because there are conflicting properties in this enterprise's organizations"
        onClose={() => null}
        title="Conflicts"
        orgConflicts={{
          totalUsageCount: 3,
          usages: [
            {name: 'acme', avatarUrl: 'avatar.com', propertyType: 'single_select'},
            {name: 'foocorp', avatarUrl: 'avatar2.com', propertyType: 'string'},
          ],
        }}
      />,
    )

    expect(
      screen.getByText(
        "This property cannot be created because there are conflicting properties in this enterprise's organizations (showing 2 out of a total 3 conflicts).",
        {exact: false},
      ),
    ).toBeInTheDocument()
  })
})
