import {mockFetch} from '@github-ui/mock-fetch'
import {render as coreRender} from '@github-ui/react-core/test-utils'
import {act, screen, waitFor} from '@testing-library/react'

import {SearchIndex} from '../search-index'
import {RefSelector, type RefSelectorProps} from '../RefSelector'

/*
 * After branch creation, we need to verify that the href is changed.
 * We can only do this properly by throwing away window.location and
 * replacing it with one that has a new setter defined on href.
 */
// @ts-expect-error overriding window.location in test
delete window.location
window.location = {} as string & Location
const setHrefSpy = jest.fn()
Object.defineProperty(window.location, 'href', {
  set: setHrefSpy,
})

beforeAll(() => {
  jest.spyOn(SearchIndex.prototype, 'render').mockImplementation(async function (this: SearchIndex) {
    act(() => this.selector.render())
  })
})

const defaultProps = {
  canCreate: true,
  cacheKey: 'fake-cache-key',
  currentCommitish: 'current-branch',
  defaultBranch: 'main',
  getHref: (ref: string) => `/href/for/${ref}`,
  owner: 'monalisa',
  repo: 'smile',
}

/**
 * RefSelector has some internal useEffect calls that perform async updates, which means we need to wrap
 * the render in an act() call.
 */
function renderRefSelector(props?: Partial<RefSelectorProps>) {
  return coreRender(<RefSelector {...defaultProps} {...props} />)
}

test('Shows the current branch in the expandable button', async () => {
  renderRefSelector()

  expect(screen.getByRole('button')).toHaveTextContent('current-branch')
})

test('Shows truncated commit oid when the selected ref is a tree', async () => {
  coreRender(
    <RefSelector
      {...defaultProps}
      currentCommitish="274fa44d7face398f34f3b7b7db142a0724fa958"
      selectedRefType="tree"
    />,
  )

  expect(screen.getByRole('button')).toHaveTextContent('274fa44')
})

test('Opens on click', async () => {
  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')
  await user.click(button)

  expect(screen.getByPlaceholderText('Find or create a branch...')).toBeInTheDocument()
  expect(screen.getByText('Switch branches/tags')).toBeInTheDocument()
  expect(screen.getByText('Branches')).toBeInTheDocument()
  expect(screen.getByText('Tags')).toBeInTheDocument()
})

test('Shows branches tab and text if types=branch provided', async () => {
  const {user} = coreRender(<RefSelector types={['branch']} {...defaultProps} />)

  const button = await screen.findByRole('button')

  await user.click(button)

  expect(screen.getByPlaceholderText('Find or create a branch...')).toBeInTheDocument()
  expect(screen.getByText('Switch branches')).toBeInTheDocument()
  expect(screen.queryByText('Branches')).not.toBeInTheDocument()
  expect(screen.queryByText('Tags')).not.toBeInTheDocument()
})

test('Shows tags tab and text if types=tag provided', async () => {
  const {user} = coreRender(<RefSelector types={['tag']} {...defaultProps} />)

  const button = await screen.findByRole('button')

  await user.click(button)

  expect(screen.getByPlaceholderText('Find a tag...')).toBeInTheDocument()
  expect(screen.getByText('Switch tags')).toBeInTheDocument()
  expect(screen.queryByText('Branches')).not.toBeInTheDocument()
  expect(screen.queryByText('Tags')).not.toBeInTheDocument()
})

test('Shows the results from the current search index', async () => {
  const mockedResults = ['main', 'current-branch', 'another-branch']

  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')

  await user.click(button)

  for (const ref of mockedResults) {
    expect(screen.getAllByText(ref).length).toBeGreaterThan(0)
  }
})

test('Virtualizes the list of results', async () => {
  const mockedResults = new Array(1_000).fill(0).map((_, i) => `mocked-branch ${i}`)

  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  // Link items on a virtualized list can cause an error in the console due to nested li's. Its not an easy problem to solve
  // because of the limitations between the virtualizer and ActionList.LinkItem, so for now just ignore that flow to prevent the
  // error from causing flakes. We should create a new test that tests both kinds of virtualized lists in the future.
  const {user} = renderRefSelector({getHref: undefined, onSelectItem: jest.fn()})
  const button = await screen.findByRole('button')

  await user.click(button)

  // Since the virtualized list relies on DOM measurement, which is not
  // possible in jest tests, the best we can do is verify that not all of the
  // refs appear in the DOM.
  expect(screen.queryAllByText('mocked-branch').length).toBeLessThan(25)
})

test('Shows a loading indicator while refs are being fetched', async () => {
  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.isLoading = true
    this.render()
  })

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')

  await user.click(button)

  expect(screen.getByLabelText('Loading branches...')).toBeInTheDocument()
})

test('Shows an error when refs cannot be fetched', async () => {
  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.fetchFailed = true
    this.render()
  })

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')

  await user.click(button)

  expect(screen.getByText('Could not load branches')).toBeInTheDocument()
})

test('Shows a zero state when no refs match the search', async () => {
  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = []
    this.isLoading = false
    this.render()
  })

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')

  await user.click(button)

  expect(screen.getByText('Nothing to show')).toBeInTheDocument()
})

test('Filters the list of refs based on the curent filter text', async () => {
  const mockedResults = ['main', 'current-branch', 'another-branch', 'this-will-appear-after-filter']

  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')

  await user.click(button)

  expect(screen.getAllByRole('menuitemradio')).toHaveLength(4)

  const input = await screen.findByPlaceholderText('Find or create a branch...')

  await user.type(input, 'filter')
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(1)

  await user.clear(input)
  expect(screen.getAllByRole('menuitemradio')).toHaveLength(4)
})

test('Allows branch creation', async () => {
  const mockCheckBranchAPI = mockFetch.mockRoute('/monalisa/smile/branches/check_tag_name_exists', undefined, {
    text: async () => '',
  })
  const mockAPI = mockFetch.mockRoute('/monalisa/smile/branches', {name: 'new-branch-name'})
  const mockedResults = ['main', 'current-branch', 'another-branch']
  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })
  const clearCacheSpy = jest.spyOn(SearchIndex.prototype, 'clearLocalStorage')

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')

  await user.click(button)

  const input = screen.getByPlaceholderText('Find or create a branch...')

  await user.type(input, 'new-branch-name')
  expect(screen.queryAllByRole('menuitemradio')).toHaveLength(0)

  const createBranchAction = screen.getByText('Create branch')

  await user.click(createBranchAction)

  expect(mockCheckBranchAPI).toHaveBeenCalledWith(
    '/monalisa/smile/branches/check_tag_name_exists',
    expect.objectContaining({method: 'POST', body: expect.any(FormData)}),
  )

  await waitFor(() => {
    expect(mockAPI).toHaveBeenCalledWith(
      '/monalisa/smile/branches',
      expect.objectContaining({method: 'POST', body: expect.any(FormData)}),
    )
  })

  expect(clearCacheSpy).toHaveBeenCalled()

  const submittedBody = mockAPI.mock.calls[0][1].body as FormData
  expect(submittedBody.get('name')).toBe('new-branch-name')
  expect(submittedBody.get('branch')).toBe('current-branch')

  await waitFor(() => expect(setHrefSpy).toHaveBeenCalledWith('/href/for/new-branch-name'))
})

test('Shows warning dialog and does not immediately create if branch matches tag', async () => {
  const mockAPI = mockFetch.mockRoute('/monalisa/smile/branches', {name: 'new-branch-name'})
  const mockCheckBranchAPI = mockFetch.mockRoute('/monalisa/smile/branches/check_tag_name_exists', undefined, {
    text: async () => 'Tag exists',
  })
  const mockedResults = ['main', 'current-branch', 'another-branch']
  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')

  await user.click(button)

  const input = screen.getByPlaceholderText('Find or create a branch...')

  await user.type(input, 'new-branch-name')
  expect(screen.queryAllByRole('menuitemradio')).toHaveLength(0)

  const createBranchAction = screen.getByText('Create branch')

  await user.click(createBranchAction)

  expect(mockCheckBranchAPI).toHaveBeenCalledWith(
    '/monalisa/smile/branches/check_tag_name_exists',
    expect.objectContaining({method: 'POST', body: expect.any(FormData)}),
  )

  await waitFor(() => {
    screen.getByText(
      'A tag already exists with the provided branch name. Many Git commands accept both tag and branch names, so creating this branch may cause unexpected behavior. Are you sure you want to create this branch?',
    )
    expect(mockAPI).not.toHaveBeenCalled()
  })

  const createButton = screen.getByText('Create')

  await user.click(createButton)

  await waitFor(() => {
    expect(mockAPI).toHaveBeenCalledWith(
      '/monalisa/smile/branches',
      expect.objectContaining({method: 'POST', body: expect.any(FormData)}),
    )
  })

  const submittedBody = mockAPI.mock.calls[0][1].body as FormData
  expect(submittedBody.get('name')).toBe('new-branch-name')
  expect(submittedBody.get('branch')).toBe('current-branch')

  await waitFor(() => expect(setHrefSpy).toHaveBeenCalledWith('/href/for/new-branch-name'))
})

test('Calls error callback if branch creation fails', async () => {
  const mockCheckBranchAPI = mockFetch.mockRoute('/monalisa/smile/branches/check_tag_name_exists', undefined, {
    text: async () => '',
  })
  mockFetch.mockRoute('/monalisa/smile/branches', {error: 'Error message'}, {ok: false})
  const mockedResults = ['main', 'current-branch', 'another-branch']
  const onErrorMock = jest.fn()

  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = coreRender(<RefSelector {...defaultProps} onCreateError={onErrorMock} />)

  const button = await screen.findByRole('button')
  await user.click(button)

  const input = screen.getByPlaceholderText('Find or create a branch...')
  await user.type(input, 'new-branch-name')

  const createBranchAction = screen.getByText('Create branch')

  await user.click(createBranchAction)

  expect(mockCheckBranchAPI).toHaveBeenCalledWith(
    '/monalisa/smile/branches/check_tag_name_exists',
    expect.objectContaining({method: 'POST', body: expect.any(FormData)}),
  )

  await waitFor(() => {
    expect(onErrorMock).toHaveBeenCalledWith('Error message')
  })
})

test('HighlightedText properly highlights provided text', async () => {
  const mockedResults = ['main', 'current-branch', 'another-branch']

  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')
  await user.click(button)

  const input = screen.getByPlaceholderText('Find or create a branch...')
  await user.type(input, 'branch')
  expect(screen.getAllByText('branch', {selector: 'strong'})).toHaveLength(2)
})

test('Text is maintained between opening and closing of ref selector dropdown', async () => {
  const mockedResults = ['main', 'current-branch', 'another-branch']

  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = renderRefSelector()
  const button = await screen.findByRole('button')

  await user.click(button)

  const input = screen.getByPlaceholderText('Find or create a branch...')

  await user.type(input, 'branch')
  expect(screen.getAllByText('branch', {selector: 'strong'})).toHaveLength(2)

  await user.click(button)

  await user.click(button)
  expect(input.getAttribute('value')).toBe('branch')
  expect(screen.getAllByText('branch', {selector: 'strong'})).toHaveLength(2)
})

test('Shows the branch icon if the selected ref is a branch', () => {
  const {container} = coreRender(<RefSelector selectedRefType="branch" {...defaultProps} />)
  // eslint-disable-next-line testing-library/no-container, testing-library/no-node-access
  expect(container.getElementsByClassName('octicon-git-branch').length).toBe(1)
  // eslint-disable-next-line testing-library/no-container, testing-library/no-node-access
  expect(container.getElementsByClassName('octicon-tag').length).toBe(0)
})

test('Shows the tag icon if the selected ref is a tag', () => {
  const {container} = coreRender(<RefSelector selectedRefType="tag" {...defaultProps} />)
  // eslint-disable-next-line testing-library/no-container, testing-library/no-node-access
  expect(container.getElementsByClassName('octicon-tag').length).toBe(1)
  // eslint-disable-next-line testing-library/no-container, testing-library/no-node-access
  expect(container.getElementsByClassName('octicon-git-branch').length).toBe(0)
})

test('Renders custom footer action link item', async () => {
  const onClickMock = jest.fn()

  const {user} = coreRender(
    <RefSelector
      {...defaultProps}
      customFooterItemProps={{
        text: 'Custom footer item',
        onClick: onClickMock,
      }}
    />,
  )

  expect(screen.queryByTestId('overlay-content')).not.toBeInTheDocument() // dialog closed

  await user.click(screen.getByRole('button')) // open dialog

  expect(screen.getByTestId('overlay-content')).toBeInTheDocument() // dialog open

  const actionLink = screen.getByRole('button', {name: 'Custom footer item'})
  expect(actionLink).toBeInTheDocument()

  await user.click(actionLink) // click footer item and close dialog

  expect(screen.queryByTestId('overlay-content')).not.toBeInTheDocument() // dialog closed
  expect(onClickMock).toHaveBeenCalled()
})

test('Calls ref change callback', async () => {
  const refChangeMock = jest.fn()
  const {user} = coreRender(<RefSelector {...defaultProps} onRefTypeChanged={refChangeMock} />)

  const button = await screen.findByRole('button')

  await user.click(button)

  await user.click(screen.getByText('Tags'))
  expect(refChangeMock).toHaveBeenCalledWith('tag')
})

test('Includes ref type in on select callback', async () => {
  const mockedResults = ['main', 'current-branch', 'another-branch']
  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })
  const onSelectMock = jest.fn()
  const {user} = coreRender(<RefSelector {...defaultProps} onSelectItem={onSelectMock} />)

  const button = await screen.findByRole('button')

  await user.click(button)

  await user.click(screen.getByText('another-branch'))
  expect(onSelectMock).toHaveBeenCalledWith('another-branch', 'branch')
})

test('has correct focus order and tab doesnt close ref selector', async () => {
  const mockedResults = ['main', 'current-branch', 'another-branch']

  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = coreRender(<RefSelector {...defaultProps} />)

  const button = await screen.findByRole('button')

  await user.click(button)

  expect(screen.getByLabelText('Cancel')).toHaveFocus()

  await user.tab()
  expect(screen.getByPlaceholderText('Find or create a branch...')).toHaveFocus()

  await user.tab()
  expect(screen.getAllByRole('tab')[0]).toHaveFocus()
  expect(screen.getAllByRole('tab')[0]).toHaveTextContent('Branches')

  await user.tab()
  expect(screen.getByRole('menuitemradio', {name: 'main default'})).toHaveFocus()

  await user.tab()
  expect(screen.getByRole('menuitemradio', {name: 'current-branch'})).toHaveFocus()

  await user.tab()
  expect(screen.getByRole('menuitemradio', {name: 'another-branch'})).toHaveFocus()

  await user.tab()
  expect(screen.getByRole('link')).toHaveFocus()
  expect(screen.getByRole('link')).toHaveTextContent('View all branches')
})

test('it creates a branch using a full commit sha', async () => {
  const mockCheckBranchAPI = mockFetch.mockRoute('/monalisa/smile/branches/check_tag_name_exists', undefined, {
    text: async () => '',
  })
  const mockAPI = mockFetch.mockRoute('/monalisa/smile/branches', {name: 'new-branch-name-two'})
  const mockedResults = ['main', 'current-branch', 'another-branch']
  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = coreRender(
    <RefSelector
      {...defaultProps}
      currentCommitish="274fa44d7face398f34f3b7b7db142a0724fa958"
      selectedRefType="tree"
    />,
  )

  const button = screen.getByRole('button', {name: '274fa44 branch'}) // short sha for display
  await user.click(button)

  const input = screen.getByPlaceholderText('Find or create a branch...')
  await user.type(input, 'new-branch-name-two')
  expect(screen.queryAllByRole('menuitemradio')).toHaveLength(0)

  const createBranchAction = screen.getByText('Create branch')

  await user.click(createBranchAction)

  await waitFor(() => {
    expect(mockCheckBranchAPI).toHaveBeenCalledWith(
      '/monalisa/smile/branches/check_tag_name_exists',
      expect.objectContaining({method: 'POST', body: expect.any(FormData)}),
    )
  })

  await waitFor(() => {
    expect(mockAPI).toHaveBeenCalledWith(
      '/monalisa/smile/branches',
      expect.objectContaining({method: 'POST', body: expect.any(FormData)}),
    )
  })

  const submittedBody = mockAPI.mock.calls[0][1].body as FormData
  expect(submittedBody.get('name')).toBe('new-branch-name-two')
  expect(submittedBody.get('branch')).toBe('274fa44d7face398f34f3b7b7db142a0724fa958') // full sha on create
})
