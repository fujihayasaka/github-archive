import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {graphql} from 'react-relay'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'

import {MESSAGES} from '../../../../constants/messages'
import {LABELS} from '../../../../constants/labels'
import {HeaderContent} from '../HeaderContent'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type React from 'react'
import HyperlistAppWrapper from '../../../../test-utils/HyperlistAppWrapper'
import type {HeaderContentCurrentViewTestQuery} from './__generated__/HeaderContentCurrentViewTestQuery.graphql'

const defaultQueryContextMocks = {
  canEditView: true,
  isEditing: false,
  isNewView: false,
  isCustomView: jest.fn().mockReturnValue(true),
  setIsEditing: jest.fn(),
}

const mockQueryContext = {
  ...defaultQueryContextMocks,
}

const defaultQueryEditContextMocks: {
  dirtyTitle: string | null
  dirtyDescription: string | null
  shouldFocusSearchOnNav: boolean
} = {
  dirtyTitle: null,
  dirtyDescription: null,
  shouldFocusSearchOnNav: false,
}

const mockQueryEditContext = {
  ...defaultQueryEditContextMocks,
}

jest.mock('../../../../contexts/QueryContext', () => {
  const originalModule = jest.requireActual('../../../../contexts/QueryContext')
  return {
    ...originalModule,
    useQueryContext: () => {
      return {
        ...originalModule.useQueryContext(),
        ...mockQueryContext,
      }
    },
    useQueryEditContext: () => {
      return {
        ...originalModule.useQueryEditContext(),
        ...mockQueryEditContext,
      }
    },
  }
})

jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

mockedUseAppPayload.mockReturnValue({
  initial_view_content: {},
  preloaded_records: [],
  enabled_features: {},
  current_user_settings: {use_single_key_shortcut: true},
  current_user: {
    avatarUrl: '',
    login: 'monalisa',
  },
})

const featureFlags = {}
jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: (flag: string) => featureFlags[flag as keyof typeof featureFlags] ?? false,
}))

beforeEach(() => {
  jest.clearAllMocks()
  Object.assign(mockQueryContext, defaultQueryContextMocks)
  Object.assign(mockQueryEditContext, defaultQueryEditContextMocks)
})

const LocalWrapper = ({children, environment}: {children: React.ReactNode; environment: RelayMockEnvironment}) => {
  return (
    <Wrapper>
      <HyperlistAppWrapper environment={environment}>{children as JSX.Element}</HyperlistAppWrapper>
    </Wrapper>
  )
}

function setup({
  isEditing = false,
  viewName = 'Test View',
  viewDescription = 'Test Description',
  readOnly = false,
} = {}) {
  const {environment} = createRelayMockEnvironment()

  mockQueryContext.isEditing = isEditing

  const {user} = renderRelay<{
    currentView: HeaderContentCurrentViewTestQuery
  }>(({queryData}) => <HeaderContent readOnly={readOnly} currentViewKey={queryData.currentView.node!} />, {
    relay: {
      queries: {
        currentView: {
          type: 'fragment',
          query: graphql`
            query HeaderContentCurrentViewTestQuery @relay_test_operation {
              node(id: "view-id") {
                ...HeaderContentCurrentViewFragment @dangerously_unaliased_fixme
              }
            }
          `,
          variables: {},
        },
      },
      mockResolvers: {
        Node() {
          return {
            id: 'view-id',
            name: viewName,
            description: viewDescription,
            icon: 'bookmark',
            color: 'blue',
          }
        },
      },
      environment,
    },
    wrapper: ({children}) => {
      return <LocalWrapper environment={environment}>{children}</LocalWrapper>
    },
  })

  return {environment, user}
}

describe('HeaderContent', () => {
  test('renders the view name when not in edit mode', async () => {
    setup()

    const heading = await screen.findByRole('heading', {level: 1})
    expect(heading).toBeInTheDocument()
    expect(heading).toHaveTextContent('Test View')
  })

  test('renders the view description when not in edit mode', async () => {
    setup()

    const description = await screen.findByText('Test Description')
    expect(description).toBeInTheDocument()
  })

  test('renders edit button when not in edit mode', async () => {
    setup()

    const editButton = await screen.findByRole('button', {
      name: LABELS.views.editButtonAriaLabel,
    })
    expect(editButton).toBeInTheDocument()
  })

  test('does not render edit button when readOnly is true', async () => {
    setup({readOnly: true})

    expect(
      screen.queryByRole('button', {
        name: LABELS.views.editButtonAriaLabel,
      }),
    ).not.toBeInTheDocument()
  })

  test('renders form controls when in edit mode', async () => {
    setup({isEditing: true})

    expect(await screen.findByRole('button', {name: LABELS.views.iconAndColorAnchorAriaLabel})).toBeInTheDocument()
    expect(await screen.findByLabelText(MESSAGES.title)).toBeInTheDocument()
    expect(await screen.findByLabelText(MESSAGES.description)).toBeInTheDocument()
  })

  test('title input has correct initial value in edit mode', async () => {
    setup({isEditing: true})

    const titleInput = await screen.findByLabelText(MESSAGES.title)
    expect(titleInput).toHaveValue('Test View')
  })

  test('description input has correct initial value in edit mode', async () => {
    setup({isEditing: true})

    const descriptionInput = await screen.findByLabelText(MESSAGES.description)
    expect(descriptionInput).toHaveValue('Test Description')
  })

  test('clicking edit button calls setIsEditing', async () => {
    const {user} = setup()

    const actionsButton = await screen.findByRole('button', {
      name: LABELS.views.editButtonAriaLabel,
    })

    await user.click(actionsButton)

    const editButton = await screen.findByRole('menuitem', {
      name: LABELS.views.edit,
    })

    await user.click(editButton)

    expect(mockQueryContext.setIsEditing).toHaveBeenCalledWith(true)
  })

  test('title validation is triggered when typing in title input', async () => {
    const {user} = setup({isEditing: true})

    const titleInput = await screen.findByLabelText(MESSAGES.title)
    await user.clear(titleInput)

    // Validation message should appear for empty title
    expect(await screen.findByText(/Title can not be empty/i)).toBeInTheDocument()
  })

  test('uses dirtyTitle value if available', async () => {
    mockQueryEditContext.dirtyTitle = 'Dirty Title'
    setup({isEditing: true})

    const titleInput = await screen.findByLabelText(MESSAGES.title)
    expect(titleInput).toHaveValue('Dirty Title')
  })

  test('uses dirtyDescription value if available', async () => {
    mockQueryEditContext.dirtyDescription = 'Dirty Description'
    setup({isEditing: true})

    const descriptionInput = await screen.findByLabelText(MESSAGES.description)
    expect(descriptionInput).toHaveValue('Dirty Description')
  })
})
