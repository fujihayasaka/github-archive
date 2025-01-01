import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DiffFileHeader} from '../DiffFileHeader'

function TestComponent() {
  return (
    <DiffFileHeader
      areLinesExpanded={false}
      canExpandOrCollapseLines={false}
      isCollapsed={false}
      canToggleRichDiff={false}
      linesAdded={3}
      path="README.md"
      newPath="README.md"
      oldPath="README.md"
      linesDeleted={2}
      linesChanged={5}
      onToggleFileCollapsed={() => false}
      onToggleExpandAllLines={() => false}
      patchStatus="MODIFIED"
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
  expect(screen.getByLabelText('collapse file: README.md')).toBeInTheDocument()
})
