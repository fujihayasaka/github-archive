import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {FilesChangedList} from '../FilesChangedList'
import {FilesChangedRow} from '../FilesChangedRow'

test('Renders the FilesChangedList', () => {
  const filesData = [
    {path: 'file', additions: 5, deletions: 10, unresolvedCommentCount: 1, status: 'M', url: 'pr/1/file'},
  ]
  render(
    <FilesChangedList
      additionCount={5}
      deletionCount={10}
      filesData={filesData}
      renderRow={file => (
        <FilesChangedRow
          key={file.path}
          additions={file.additions}
          changeType={file.status}
          deletions={file.deletions}
          filePathUrl={file.url}
          path={file.path}
          unresolvedCommentCount={0}
        />
      )}
    />,
  )
  expect(screen.getByText('+5')).toBeInTheDocument()
  expect(screen.getByText('-10')).toBeInTheDocument()
  expect(screen.getByText('file')).toBeInTheDocument()
})
