import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, within} from '@storybook/test'
import {shouldInteractionPlay} from '@github-ui/storybook'
import {FileFilter} from './FileFilter'
import {getMockFileTreePageData, getMockSpecialFileTreePageData} from '../test-utils/mock-data'

const meta: Meta<typeof FileFilter> = {
  title: 'Pull Requests/FileTree/FileFilter',
  component: FileFilter,
} satisfies Meta<typeof FileFilter>

type Story = StoryObj<typeof FileFilter>

export const With_No_Special_Filters: Story = {
  render: () => (
    <FileFilter
      diffs={[getMockFileTreePageData().diffs[0]!, getMockFileTreePageData().diffs[3]!]}
      fileFilterState={{filterText: '', fileExtensions: new Set(['.js', '.css']), unselectedFileExtensions: new Set()}}
      setFileFilterState={() => {}}
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    await step('It renders a filter input', async () => {
      expect(canvas.getByRole('textbox', {name: 'Filter files…'})).toBeInTheDocument()
    })

    await step('Clicking the button opens the filter menu', async () => {
      const filterButton = canvas.getByRole('button', {name: 'Filter'})
      await userEvent.click(filterButton)
      const menu = canvas.getByRole('menu')

      expect(within(menu).getByText('File extensions')).toBeInTheDocument()
      expect(within(menu).getByRole('menuitemcheckbox', {name: '.js'})).toBeInTheDocument()
      expect(within(menu).getByRole('menuitemcheckbox', {name: '.css'})).toBeInTheDocument()
    })

    await step('Extra filters are not visible if there are no special files', async () => {
      const codeownersFilter = canvas.queryByRole('menuitemradio', {name: 'Only files owned by you'})
      expect(codeownersFilter).not.toBeInTheDocument()

      const onlyManifestFilesFilter = canvas.queryByRole('menuitemradio', {name: 'Only manifest files'})
      expect(onlyManifestFilesFilter).not.toBeInTheDocument()

      const deletedFilesFilter = canvas.queryByRole('menuitemradio', {name: 'Deleted files'})
      expect(deletedFilesFilter).not.toBeInTheDocument()

      const vendorFilesFilter = canvas.queryByRole('menuitemradio', {name: 'Vendored files'})
      expect(vendorFilesFilter).not.toBeInTheDocument()
    })
  },
}

export const With_Special_Filters: Story = {
  render: () => (
    <FileFilter
      diffs={getMockSpecialFileTreePageData().diffs}
      fileFilterState={{
        filterText: '',
        fileExtensions: new Set(['.js', '.css']),
        unselectedFileExtensions: new Set(),
      }}
      setFileFilterState={() => {}}
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    await step('It renders a filter input', async () => {
      expect(canvas.getByRole('textbox', {name: 'Filter files…'})).toBeInTheDocument()
    })

    await step('Clicking the button opens the filter menu', async () => {
      const filterButton = canvas.getByRole('button', {name: 'Filter'})
      await userEvent.click(filterButton)

      const menu = canvas.getByRole('menu')
      expect(within(menu).getByText('File extensions')).toBeInTheDocument()
      expect(within(menu).getByRole('menuitemcheckbox', {name: '.js'})).toBeInTheDocument()
      expect(within(menu).getByRole('menuitemcheckbox', {name: '.css'})).toBeInTheDocument()
    })

    await step('Extra filters are visible if there are special files', async () => {
      const codeownersFilter = canvas.getByRole('menuitemradio', {name: 'Only files owned by you'})
      expect(codeownersFilter).toBeInTheDocument()

      const onlyManifestFilesFilter = canvas.getByRole('menuitemradio', {name: 'Only manifest files'})
      expect(onlyManifestFilesFilter).toBeInTheDocument()

      const deletedFilesFilter = canvas.getByRole('menuitemradio', {name: 'Deleted files'})
      expect(deletedFilesFilter).toBeInTheDocument()

      const vendorFilesFilter = canvas.getByRole('menuitemradio', {name: 'Vendored files'})
      expect(vendorFilesFilter).toBeInTheDocument()
    })
  },
}

export default meta
