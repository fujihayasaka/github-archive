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
          <StatusCheckRow
            displayName="Check"
            additionalContext="additional context"
            description="Description"
            state="SUCCESS"
            targetUrl={undefined}
          />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>,
  )
  expect(screen.getByText(/additional context/)).toBeInTheDocument()
  expect(screen.getByText('Check')).toBeInTheDocument()
  expect(screen.getByText(/— Description/)).toBeInTheDocument()
  expect(screen.queryByRole('link')).not.toBeInTheDocument()
})

test('status check row displays additional context as queued when state is queued', () => {
  render(
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="test checks group">
          <StatusCheckRow
            displayName="Check"
            additionalContext="additional context"
            description="Description"
            state="QUEUED"
            targetUrl={undefined}
          />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>,
  )
  expect(screen.queryByText(/additional contex/)).not.toBeInTheDocument()
  expect(screen.getByText(/Queued/)).toBeInTheDocument()
  expect(screen.getByText('Check')).toBeInTheDocument()
  expect(screen.getByText(/— Description/)).toBeInTheDocument()
  expect(screen.queryByRole('link')).not.toBeInTheDocument()
})

describe('when copilot check run failure context is not provided', () => {
  test('status check row does not render a menu button', () => {
    render(
      <IdProvider>
        <VariantProvider>
          <TitleProvider title="test checks group">
            <StatusCheckRow
              displayName="Check"
              additionalContext="additional context"
              description="Description"
              state="SUCCESS"
              targetUrl={undefined}
            />
          </TitleProvider>
        </VariantProvider>
      </IdProvider>,
    )
    expect(screen.queryByTestId('overflow-menu-anchor')).not.toBeInTheDocument()
  })
})

describe('when copilot check run failure context is provided', () => {
  test('status check row renders a menu button', async () => {
    render(
      <IdProvider>
        <VariantProvider>
          <TitleProvider title="test checks group">
            <StatusCheckRow
              displayName="Check"
              additionalContext="additional context"
              description="Description"
              state="SUCCESS"
              targetUrl={undefined}
              copilotCheckRunFailureContext={{jobId: 12345}}
              reserveSpaceForActionBar
            />
          </TitleProvider>
        </VariantProvider>
      </IdProvider>,
    )
    expect(await screen.findByTestId('overflow-menu-anchor')).toBeInTheDocument()
  })
})

test('status check row contains the proper aria-label', () => {
  render(
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="test checks group">
          <StatusCheckRow
            displayName="Check"
            additionalContext="timed out after 10s"
            description="Description"
            state="SUCCESS"
            targetUrl={undefined}
          />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>,
  )
  expect(screen.getByLabelText('Check timed out after 10s')).toBeInTheDocument()
})

test('status check row does not render a required badge when reserveSpaceForRequiredBadge is false', () => {
  render(
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="test checks group">
          <StatusCheckRow
            displayName="Check"
            additionalContext="additional context"
            description="Description"
            state="SUCCESS"
            targetUrl={undefined}
            reserveSpaceForRequiredBadge={false}
          />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>,
  )
  expect(screen.queryByTestId('required-badge')).not.toBeInTheDocument()
})

test('status check row renders a required badge when reserveSpaceForRequiredBadge is true', () => {
  render(
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="test checks group">
          <StatusCheckRow
            displayName="Check"
            additionalContext="additional context"
            description="Description"
            state="SUCCESS"
            targetUrl={undefined}
            isRequired
            reserveSpaceForRequiredBadge
          />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>,
  )
  expect(screen.getByText('Required')).toBeInTheDocument()
})

test('status check row does not render menu button when reserveSpaceForActionBar is false', () => {
  render(
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="test checks group">
          <StatusCheckRow
            displayName="Check"
            additionalContext="additional context"
            description="Description"
            state="SUCCESS"
            targetUrl={undefined}
            reserveSpaceForActionBar={false}
          />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>,
  )
  expect(screen.queryByRole('button', {name: 'More actions'})).not.toBeInTheDocument()
})

test('status check row renders menu button when reserveSpaceForActionBar is true', () => {
  render(
    <IdProvider>
      <VariantProvider>
        <TitleProvider title="test checks group">
          <StatusCheckRow
            displayName="Check"
            additionalContext="additional context"
            description="Description"
            state="SUCCESS"
            targetUrl={undefined}
            copilotCheckRunFailureContext={{jobId: 12345}}
            reserveSpaceForActionBar
          />
        </TitleProvider>
      </VariantProvider>
    </IdProvider>,
  )
  expect(screen.getByRole('button', {name: 'More actions'})).toBeInTheDocument()
})
