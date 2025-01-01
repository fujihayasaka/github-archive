import {render, screen} from '@testing-library/react'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'

import {StatusCheckRow} from '../StatusCheckRow'

test('status check row does not include links when target URL is null', () => {
  render(
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="test checks group">
          <StatusCheckRow displayName="Check" description="Description" state="SUCCESS" targetUrl={undefined} />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>,
  )
  expect(screen.getByText('Check')).toBeInTheDocument()
  expect(screen.getByText('Description')).toBeInTheDocument()
  expect(screen.queryByRole('link')).not.toBeInTheDocument()
})
