import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor, within} from '@testing-library/react'
import type {OperationDescriptor} from 'relay-runtime'
import {MockPayloadGenerator} from 'relay-test-utils'

import {TestProjectPickerComponent, buildProject} from '../test-utils/ProjectPickerHelpers'
import {ProjectPickerGraphqlQuery} from '../components/ProjectPicker'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'

const mockUseFeatureFlags = jest.fn().mockReturnValue({})
jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlags: () => mockUseFeatureFlags({}),
}))

beforeEach(() => {
  mockUseFeatureFlags.mockClear()
})

test('render projects when clicking on the anchor', async () => {
  const environment = setupEnvironment()

  const {user} = render(
    <TestProjectPickerComponent environment={environment} shortcutEnabled={false} readonly={false} />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('projectA')
  expect(options[1]).toHaveTextContent('projectB')
})

test('render warning for a project in the list where the item limit is hit', async () => {
  const environment = setupEnvironment()

  const {user} = render(
    <TestProjectPickerComponent environment={environment} shortcutEnabled={false} readonly={false} />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).not.toHaveTextContent('To add more, please archive or delete existing items from it.')
  expect(options[2]).toHaveTextContent('To add more, please archive or delete existing items from it.')
})

test('show a dialog when closing the picker after having selected a project where the item limit is hit', async () => {
  const environment = setupEnvironment()

  const {user} = render(
    <TestProjectPickerComponent environment={environment} shortcutEnabled={false} readonly={false} />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = await screen.findAllByRole('option')

  // select the project with the item limit
  if (options[2]) {
    await user.click(options[2])
  }

  // Closing the picker by clicking outside of it
  await user.click(document.body)

  await screen.findByText('Project limits reached')
})

test('correctly selecting projects when the selection contains valid and invalid projects', async () => {
  const environment = setupEnvironment()
  const mutation = jest.fn()

  const {user} = render(
    <TestProjectPickerComponent environment={environment} shortcutEnabled={false} readonly={false} onSave={mutation} />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  expect(await screen.findAllByRole('option')).toHaveLength(3)

  const options = await screen.findAllByRole('option')

  if (options[0] && options[2]) {
    await user.click(options[0]) // Valid project
    // await user.click(options[2]) // Invalid project
  }

  // Closing the picker
  await user.click(document.body)

  //Expect that the invalid project is not in the selected projects
  expect(mutation).not.toHaveBeenCalledWith(
    expect.objectContaining({
      title: 'projectA',
    }),
  )

  //Expect that the invalid project is not in the selected projects
  expect(mutation).not.toHaveBeenCalledWith(
    expect.objectContaining({
      title: 'projectC',
    }),
  )
})

test('render projects when hitting shortcut key', async () => {
  const environment = setupEnvironment()

  const {user} = render(<TestProjectPickerComponent environment={environment} shortcutEnabled readonly={false} />)

  await user.keyboard('p')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('projectA')
  expect(options[1]).toHaveTextContent('projectB')
})

test('renders projects as disabled where user has no write permissions', async () => {
  const environment = setupEnvironment({viewerCanCreateProjects: false})

  const {user} = render(
    <TestProjectPickerComponent environment={environment} shortcutEnabled={false} readonly={false} />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = await screen.findAllByRole('option')

  const firstOptionChildElements = within(options[0]!).queryAllByRole('generic', {hidden: true})
  expect(firstOptionChildElements[1]).not.toHaveAttribute('disabled')

  const secondOptionChildElements = within(options[1]!).queryAllByRole('generic', {hidden: true})
  expect(secondOptionChildElements[1]).toHaveAttribute('disabled')
})

test('pressing space while on a selected should toggle the selection', async () => {
  const environment = setupEnvironment()
  const selectedProject = buildProject({title: 'selectedProject', closed: false})

  const {user} = render(
    <TestProjectPickerComponent
      environment={environment}
      shortcutEnabled={false}
      readonly={false}
      selectedProjects={[selectedProject]}
    />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(4)
  })

  let options = await screen.findAllByRole('option')

  await user.keyboard('[arrowdown]')

  // We use the 2nd option, since a key down press will go to the 2nd option given the first one is already indirectly
  // activated. This is the primer behaviour.
  expect(options[1]).toHaveAttribute('data-is-active-descendant', 'activated-directly')

  await user.keyboard('[space]')
  await waitFor(async () => {
    options = await screen.findAllByRole('option')
    expect(options[1]).toHaveAttribute('aria-selected', 'true')
  })
  // Press space again to deselect the first option
  await user.keyboard('[space]')
  // Assert selection status
  expect(options[1]).toHaveAttribute('aria-selected', 'false')
})

test('renders selected projects', async () => {
  const environment = setupEnvironment()
  const selectedProject = buildProject({title: 'selectedProject', closed: false})
  const selectedProject2 = buildProject({title: 'selectedProject2', closed: false})

  const {user} = render(
    <TestProjectPickerComponent
      environment={environment}
      shortcutEnabled={false}
      readonly={false}
      selectedProjects={[selectedProject, selectedProject2]}
    />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  // assert that 3 options are visible including the selected one
  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(5)
  })

  const options = await screen.findAllByRole('option')

  // assert that selectedProject appears first
  expect(options[0]).toHaveTextContent('selectedProject')
  expect(options[1]).toHaveTextContent('selectedProject2')
  expect(options[2]).toHaveTextContent('projectA')
  expect(options[3]).toHaveTextContent('projectB')

  // assert that selected project is actually selected
  expect(options[0]).toHaveAttribute('aria-selected', 'true')
  expect(options[1]).toHaveAttribute('aria-selected', 'true')
  expect(options[2]).toHaveAttribute('aria-selected', 'false')
  expect(options[3]).toHaveAttribute('aria-selected', 'false')
})

test('shows first selected project title', async () => {
  const environment = setupEnvironment()
  const selectedProject = buildProject({
    title: 'Project title with a very long name for a title. If we continue typing this title will be extremely long.',
    closed: false,
  })

  render(
    <TestProjectPickerComponent
      environment={environment}
      shortcutEnabled={false}
      readonly={false}
      firstSelectedProjectTitle={selectedProject.title}
    />,
  )

  const button = await screen.findByRole('button')

  await waitFor(() => {
    expect(button).toHaveTextContent(selectedProject.title)
  })
})

function setupEnvironment(overwrites?: object) {
  const {environment} = createRelayMockEnvironment()

  environment.mock.queuePendingOperation(ProjectPickerGraphqlQuery, {
    owner: 'github',
    repo: 'issues',
    query: 'some query',
  })
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          projectsV2: {
            nodes: [
              buildProject({title: 'projectA', closed: false, viewerCanUpdate: true}),
              buildProject({title: 'projectB', closed: false, viewerCanUpdate: false}),
              buildProject({title: 'projectC', closed: false, hasReachedItemsLimit: true}),
            ],
          },
          recentProjects: {edges: []},
          owner: {
            projectsV2: {edges: []},
            recentProjects: {edges: []},
          },
          ...overwrites,
        }
      },
    })
  })

  return environment
}
