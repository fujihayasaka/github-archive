import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {IssueSummary} from '../IssueSummary'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'

test('Renders skeleton text', () => {
  const props = {isPending: true, isError: false, summary: undefined, error: null}

  render(
    <VariantProvider>
      <IssueSummary {...props} />
    </VariantProvider>,
  )

  expect(screen.getByTestId('summary-skeleton-text')).toBeInTheDocument()
})

test('Renders an error message', () => {
  const error = new Error('Something went wrong')
  const props = {isPending: false, isError: true, summary: undefined, error}

  render(
    <VariantProvider>
      <IssueSummary {...props} />
    </VariantProvider>,
  )

  expect(screen.getByText('Something went wrong')).toBeInTheDocument()
})

test('Render the summary', () => {
  const summary = 'This is a summary'
  const props = {isPending: false, isError: false, summary, error: null}

  render(
    <VariantProvider>
      <IssueSummary {...props} />
    </VariantProvider>,
  )

  expect(screen.getByText(summary)).toBeInTheDocument()
})
