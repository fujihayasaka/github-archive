import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import FileList from './FileList'

const meta: Meta<typeof FileList> = {
  title: 'Apps/GitHub Models/RAG/FileList',
  component: FileList,
  decorators: [
    Story => (
      <div style={{width: '100%', maxWidth: '500px', padding: '1rem'}}>
        <Story />
      </div>
    ),
  ],
}

export default meta

type Story = StoryObj<typeof FileList>

const args = {
  files: [
    // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
    {file: new File(['contents'], 'file1.txt')},
    // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
    {file: new File(['contents'], 'file2.txt')},
    // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
    {file: new File(['contents'], 'a-really-long-file-name-to-test-overflow-when-the-file-name-is-too-long.txt')},
  ],
  onFileDeleted: fn(),
}

export const Default: Story = {
  args,
}

export const NoOnFileDelete: Story = {
  args: {
    files: args.files,
  },
}

export const FileIsUploading: Story = {
  args: {
    ...args,
    files: [
      // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
      {file: new File(['contents'], 'file1.txt'), isUploadInProgress: true},
      // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
      {file: new File(['contents'], 'file2.txt')},
      // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
      {file: new File(['contents'], 'file3.txt')},
    ],
  },
}

export const Disabled: Story = {
  args: {
    files: args.files,
    disabled: true,
  },
}
