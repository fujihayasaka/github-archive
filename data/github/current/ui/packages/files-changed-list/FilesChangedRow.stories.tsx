import type {Meta} from '@storybook/react'
import {FilesChangedRow, type FilesChangedRowProps} from './FilesChangedRow'
import {ListView} from '@github-ui/list-view'
import {AppContext} from '@github-ui/react-core/app-context'
import {MemoryRouter} from 'react-router-dom'

const meta = {
  title: 'Recipes/FilesChangedRow',
  component: FilesChangedRow,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof FilesChangedRow>

export default meta

const defaultArgs: Partial<FilesChangedRowProps> = {
  path: 'file',
  additions: 5,
  deletions: 10,
  unresolvedCommentCount: 1,
  changeType: 'M',
  filePathUrl: 'pr/1/file',
}

export const FilesChangedRowExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: FilesChangedRowProps) => {
    return (
      <AppContext.Provider
        value={{
          routes: [],
        }}
      >
        <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
          <ListView title="Files">
            <FilesChangedRow {...args} />
          </ListView>
        </MemoryRouter>
      </AppContext.Provider>
    )
  },
}
