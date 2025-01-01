import {render} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ComponentWithPreloadedQueryRef} from '@github-ui/relay-test-utils/RelayComponents'
import {screen} from '@testing-library/react'
import type {PreloadedQuery} from 'react-relay/hooks'
import {createMockEnvironment} from 'relay-test-utils'

import {KNOWN_VIEWS} from '../../../constants/view-constants'
import HyperlistAppWrapper from '../../../test-utils/HyperlistAppWrapper'
import SavedViewsGraphqlQuery, {type SavedViewsQuery} from '../__generated__/SavedViewsQuery.graphql'
import {Sidebar} from '../Sidebar'

jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

const environment = createMockEnvironment()

function TestComponent() {
  // eslint-disable-next-line @eslint-react/no-nested-component-definitions
  function WrappedSidebar({queryRef}: {queryRef: PreloadedQuery<SavedViewsQuery>}) {
    return <Sidebar customViewsRef={queryRef} />
  }
  return (
    <HyperlistAppWrapper environment={environment}>
      <ComponentWithPreloadedQueryRef component={WrappedSidebar} query={SavedViewsGraphqlQuery} queryVariables={{}} />
    </HyperlistAppWrapper>
  )
}

test('renders known views', async () => {
  mockedUseAppPayload.mockReturnValue({
    initial_view_content: {},
  })

  render(<TestComponent />)

  for (const knownView of KNOWN_VIEWS.filter(v => !v.hidden)) {
    await expect(screen.findByText(knownView.name)).resolves.toBeInTheDocument()
  }
})
