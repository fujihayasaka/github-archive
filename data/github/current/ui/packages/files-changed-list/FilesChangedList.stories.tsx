import type {Meta} from '@storybook/react'
import {FilesChangedList, type FilesChangedListProps} from './FilesChangedList'
import {FilesChangedRow, type FilesChangedRowProps} from './FilesChangedRow'
import {RoutesContext} from '@github-ui/react-core/routes-context'
import {MemoryRouter} from 'react-router-dom'

const meta = {
  title: 'Recipes/FilesChangedList',
  component: FilesChangedList,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof FilesChangedList>

export default meta

const defaultArgs: Partial<FilesChangedListProps<FilesChangedRowProps>> = {
  additionCount: 5,
  deletionCount: 10,
  filesChangedPath: 'pr/1/files',
  filesData: [
    {path: 'file', additions: 5, deletions: 10, unresolvedCommentCount: 1, changeType: 'M', filePathUrl: 'pr/1/file'},
  ],
  renderRow: file => <FilesChangedRow key={file.path} {...file} />,
  maxFilesToShow: 15,
}

export const FilesChangedListExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: FilesChangedListProps<FilesChangedRowProps>) => {
    return (
      <RoutesContext.Provider
        value={{
          routes: [],
        }}
      >
        <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
          <FilesChangedList {...args} />
        </MemoryRouter>
      </RoutesContext.Provider>
    )
  },
}
