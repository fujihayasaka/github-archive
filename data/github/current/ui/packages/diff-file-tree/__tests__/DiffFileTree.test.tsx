import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DiffFileTree} from '../DiffFileTree'

function TestComponent({renderPattern}: {renderPattern: 'grouped' | 'traditional'}) {
  return (
    <DiffFileTree
      renderPattern={renderPattern}
      diffs={[
        {
          path: 'src/Components/Component.tsx',
          pathDigest: 'test-digest',
          changeType: 'ADDED',
        },
        {
          path: 'src/Components/Tree.tsx',
          pathDigest: 'test-digest',
          changeType: 'RENAMED',
        },
        {
          path: 'README.md',
          pathDigest: 'test-digest',
          changeType: 'MODIFIED',
          totalCommentsCount: 1,
        },
        {
          path: 'file.rb',
          pathDigest: 'test-digest',
          changeType: 'DELETED',
          totalCommentsCount: 2,
        },
        {
          path: 'very-last-file.rb',
          pathDigest: 'test-digest',
          changeType: 'MODIFIED',
        },
      ]}
    />
  )
}

test('Renders the DiffFileTree with the grouped render pattern', () => {
  render(<TestComponent renderPattern="grouped" />)
  expect(screen.getByLabelText('File Tree')).toBeInTheDocument()
  expect(screen.getByText('src/Components')).toBeInTheDocument()
  expect(screen.getByText('Component.tsx')).toBeInTheDocument()
  expect(screen.getByText('Tree.tsx')).toBeInTheDocument()
  expect(screen.getByText('README.md')).toBeInTheDocument()
  expect(screen.getByText('file.rb')).toBeInTheDocument()
  expect(screen.getByText('very-last-file.rb')).toBeInTheDocument()
  expect(screen.getByText('has 2 comments', {selector: '.sr-only'})).toBeInTheDocument()
  expect(screen.getByText('has 1 comment', {selector: '.sr-only'})).toBeInTheDocument()
})

test('Renders the DiffFileTree with the traditional render pattern', () => {
  render(<TestComponent renderPattern="traditional" />)
  expect(screen.getByLabelText('File Tree')).toBeInTheDocument()
  expect(screen.getByText('src/Components')).toBeInTheDocument()
  expect(screen.getByText('Component.tsx')).toBeInTheDocument()
  expect(screen.getByText('Tree.tsx')).toBeInTheDocument()
  expect(screen.getByText('README.md')).toBeInTheDocument()
  expect(screen.getByText('file.rb')).toBeInTheDocument()
  expect(screen.getByText('very-last-file.rb')).toBeInTheDocument()
  expect(screen.getByText('has 2 comments', {selector: '.sr-only'})).toBeInTheDocument()
  expect(screen.getByText('has 1 comment', {selector: '.sr-only'})).toBeInTheDocument()
})

test('Renders the DiffFileTree in the correct order with the traditional render pattern - alphabetic path', () => {
  render(<TestComponent renderPattern="traditional" />)

  const treeEntries = screen.getAllByRole('treeitem')

  expect(treeEntries[0]).toHaveTextContent('README.md')
  expect(treeEntries[1]).toHaveTextContent('file.rb')
  expect(treeEntries[2]).toHaveTextContent('src/Components')
  expect(treeEntries[3]).toHaveTextContent('Component.tsx')
  expect(treeEntries[4]).toHaveTextContent('Tree.tsx')
  expect(treeEntries[5]).toHaveTextContent('very-last-file.rb')
})

test('Renders the DiffFileTree in the correct order with the grouped render pattern - files then directories', () => {
  render(<TestComponent renderPattern="grouped" />)

  const treeEntries = screen.getAllByRole('treeitem')

  expect(treeEntries[0]).toHaveTextContent('README.md')
  expect(treeEntries[1]).toHaveTextContent('file.rb')
  expect(treeEntries[2]).toHaveTextContent('very-last-file.rb')
  expect(treeEntries[3]).toHaveTextContent('src/Components')
  expect(treeEntries[4]).toHaveTextContent('Component.tsx')
  expect(treeEntries[5]).toHaveTextContent('Tree.tsx')
})
