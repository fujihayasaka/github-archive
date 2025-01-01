import '../test-utils/mocks'

import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {App} from '../App'
import {EditorMode, MarkdownEditor, type MarkdownEditorProps} from '../components/MarkdownEditor'
import {processRelativeImagePaths} from '../hooks/use-markdown-preview'
import {getWorkspaceEditorRoutePayload} from '../test-utils/mock-data'

function TestComponent(props: Partial<MarkdownEditorProps>) {
  return (
    <App>
      <MarkdownEditor
        height={'100%'}
        editorMode={EditorMode.Edit}
        showDiff={false}
        saveChanges={() => {}}
        diffEditorSettings={{}}
        editorSettings={{}}
        {...props}
      />
    </App>
  )
}
describe('MarkdownEditor', () => {
  test('renders editor-only mode', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    render(<TestComponent />, {
      pathname: '/monalisa/smile/pull/1/edit/new',
      routePayload,
    })

    expect(screen.getByText("I'M MONACO!")).toBeInTheDocument()
    expect(screen.queryByRole('heading', {level: 1})).not.toBeInTheDocument()
  })

  test('renders preview-only mode', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    render(<TestComponent editorMode={EditorMode.Preview} editorSettings={{value: '# Title'}} />, {
      pathname: '/monalisa/smile/pull/1/edit/new',
      routePayload,
    })

    expect(screen.queryByText("I'M MONACO!")).not.toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1})).toBeInTheDocument()
  })

  test('renders side-by-side mode', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    render(<TestComponent editorMode={EditorMode.Split} editorSettings={{value: '# Title'}} />, {
      pathname: '/monalisa/smile/pull/1/edit/new',
      routePayload,
    })

    expect(screen.getByText("I'M MONACO!")).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1})).toBeInTheDocument()
  })

  test('renders editor-only mode with diff editor', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    const diffEditorProps = {original: '# Original Heading', modified: '# Modified Heading'}
    render(<TestComponent showDiff diffEditorSettings={diffEditorProps} />, {
      pathname: '/monalisa/smile/pull/1/edit/new',
      routePayload,
    })

    expect(screen.getByText("I'M THE MONACO DIFF EDITOR!")).toBeInTheDocument()
    expect(screen.queryByRole('heading', {level: 1})).not.toBeInTheDocument()
  })

  test('renders preview-only mode when viewing diffs', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    const diffEditorProps = {original: '# Original Heading', modified: '# Modified Heading'}
    render(<TestComponent editorMode={EditorMode.Preview} showDiff diffEditorSettings={diffEditorProps} />, {
      pathname: '/monalisa/smile/pull/1/edit/new',
      routePayload,
    })

    expect(screen.queryByText("I'M THE MONACO DIFF EDITOR!")).not.toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1})).toBeInTheDocument()
  })

  test('renders side-by-side mode with diff editor', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    const diffEditorProps = {original: '# Original Heading', modified: '# Modified Heading'}
    render(<TestComponent editorMode={EditorMode.Split} showDiff diffEditorSettings={diffEditorProps} />, {
      pathname: '/monalisa/smile/pull/1/edit/new',
      routePayload,
    })

    expect(screen.getByText("I'M THE MONACO DIFF EDITOR!")).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1})).toBeInTheDocument()
  })
})

describe('processRelativeImagePaths', () => {
  test('does not modify the src of an image tag with an absolute URL', () => {
    const imgNode = document.createElement('img')
    imgNode.setAttribute('src', 'https://example.com/image.png')

    processRelativeImagePaths(imgNode, 'owner/repo', 'main')

    expect(imgNode.getAttribute('src')).toBe('https://example.com/image.png')
  })

  test('does not modify protocol-relative URLS', () => {
    const imgNode = document.createElement('img')
    imgNode.setAttribute('src', '//example.com/path/to/resource')

    processRelativeImagePaths(imgNode, 'owner/repo', 'main')

    expect(imgNode.getAttribute('src')).toBe('//example.com/path/to/resource')
  })

  test('does not modify anchor links', () => {
    const imgNode = document.createElement('img')
    imgNode.setAttribute('src', '#anchor')

    processRelativeImagePaths(imgNode, 'owner/repo', 'main')

    expect(imgNode.getAttribute('src')).toBe('#anchor')
  })

  test('handles urls for images in the PR head branch', () => {
    const imgNode = document.createElement('img')
    imgNode.setAttribute('src', 'assets/images/image.png')

    processRelativeImagePaths(imgNode, 'owner/repo', 'branch-1')

    expect(imgNode.getAttribute('src')).toBe('/owner/repo/raw/branch-1/assets/images/image.png')
  })

  test('handles urls for images in the PR base branch', () => {
    const imgNode = document.createElement('img')
    imgNode.setAttribute('src', '/../base-branch/assets/images/image.png')

    processRelativeImagePaths(imgNode, 'owner/repo', 'head-branch')

    expect(imgNode.getAttribute('src')).toBe('/owner/repo/raw/base-branch/assets/images/image.png')
  })

  test('handles urls for images in the PR default branch', () => {
    const imgNode = document.createElement('img')
    imgNode.setAttribute('src', '/../../main/assets/images/image.png')

    processRelativeImagePaths(imgNode, 'owner/repo', 'head-branch')

    expect(imgNode.getAttribute('src')).toBe('/owner/repo/raw/main/assets/images/image.png')
  })
})
