import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DiffFileHeader} from '../DiffFileHeader'

function TestComponent({oldPath = 'README.md', patchStatus = 'MODIFIED'}) {
  return (
    <DiffFileHeader
      areLinesExpanded={false}
      canExpandOrCollapseLines={false}
      isCollapsed={false}
      canToggleRichDiff={false}
      linesAdded={3}
      path="README.md"
      newPath="README.md"
      oldPath={oldPath}
      linesDeleted={2}
      linesChanged={5}
      onToggleFileCollapsed={() => false}
      onToggleExpandAllLines={() => false}
      patchStatus={patchStatus}
      fileLinkHref="#README.md"
    />
  )
}
function addLRMMarkToString(str: string) {
  return `\u200E${str}`
}

test('Renders diff file header', () => {
  render(<TestComponent />)
  expect(screen.getByText(addLRMMarkToString('README.md'))).toBeInTheDocument()
  expect(screen.getByText('+3')).toBeInTheDocument()
  expect(screen.getByText('-2')).toBeInTheDocument()
  expect(screen.getByLabelText('Collapse file: README.md')).toBeInTheDocument()
  const expectedHeadingText = addLRMMarkToString('README.md')
  expect(screen.getByRole('heading', {level: 3, name: expectedHeadingText})).toBeInTheDocument()
})

test('communicates when files are renamed to assistive technology users', () => {
  render(<TestComponent patchStatus="RENAMED" oldPath="my-old-README.md" />)
  const expectedHeadingText = `${addLRMMarkToString('my-old-README.md')} renamed to ${addLRMMarkToString('README.md')}`
  expect(screen.getByRole('heading', {level: 3, name: expectedHeadingText})).toBeInTheDocument()
})
