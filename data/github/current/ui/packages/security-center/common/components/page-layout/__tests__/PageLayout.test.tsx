import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import {VisibilityFilterProvider} from '../../../filter-providers'
import PageLayout from '../../page-layout'

it('renders a filter validity banner when filter is invalid', async () => {
  render(
    <PageLayout>
      <PageLayout.FilterBar
        filter={
          <PageLayout.Filter providers={[new VisibilityFilterProvider()]} query={'visibility:'} onSubmit={() => {}} />
        }
        revert={<PageLayout.FilterRevert show={false} onRevert={() => {}} />}
      />
    </PageLayout>,
  )

  await waitFor(() =>
    expect(screen.getByTestId('validation-error-list').textContent).toBe('Empty value for visibility'),
  )
})
