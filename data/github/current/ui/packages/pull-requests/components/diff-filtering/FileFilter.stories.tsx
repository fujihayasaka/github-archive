import {MemoryRouter} from 'react-router-dom'
import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, waitFor, within} from '@storybook/test'
import {shouldInteractionPlay} from '@github-ui/storybook'
import {FileFilter} from './FileFilter'
import {getMockFileFilterPageData} from '../../test-utils/files-changed/file-filter-mock-data'
import {mockCodeownersData} from '../../test-utils/files-changed/codeowners-mock-data'
import {http, HttpResponse} from 'msw'
import {codeownersApiUrl} from '../../page-data/loaders/use-codeowners-data'

const defaultData = getMockFileFilterPageData()

const codeownersRoute = codeownersApiUrl(defaultData.basePath)
const defaultHandlers = [
  http.get(codeownersRoute, () => {
    return HttpResponse.json(mockCodeownersData({}))
  }),
]

const meta: Meta<typeof FileFilter> = {
  title: 'Pull Requests/FileTree/FileFilter',
  component: FileFilter,
  decorators: [
    Story => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
} satisfies Meta<typeof FileFilter>

type Story = StoryObj<typeof FileFilter>

export const CanSeeDefaultFilterOptions: Story = {
  render: () => (
    <FileFilter
      basePath={defaultData.basePath}
      fileFilterMenuOptions={{
        ...defaultData.fileFilterMenuOptions,
        canSeeDeletedFilesFilter: false,
      }}
      fileFilterState={{
        ...defaultData.fileFilterState,
        fileExtensions: {
          '.js': 1,
          '.css': 2,
        },
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
      const filterButton = canvas.getByRole('button', {name: 'Filter options'})
      await userEvent.click(filterButton)
      const menu = canvas.getByRole('menu')

      expect(within(menu).getByText('File extensions')).toBeInTheDocument()
      expect(within(menu).getByRole('menuitemcheckbox', {name: '.js (1)'})).toBeInTheDocument()
      expect(within(menu).getByRole('menuitemcheckbox', {name: '.css (2)'})).toBeInTheDocument()
    })

    await step('Extra filters are not visible if there are no special files', async () => {
      const codeownersFilter = canvas.queryByRole('menuitemcheckbox', {name: /Only files owned by you/i})
      expect(codeownersFilter).not.toBeInTheDocument()

      const onlyManifestFilesFilter = canvas.queryByRole('menuitemcheckbox', {name: 'Only manifest files'})
      expect(onlyManifestFilesFilter).not.toBeInTheDocument()

      const deletedFilesFilter = canvas.queryByRole('menuitemcheckbox', {name: 'Deleted files'})
      expect(deletedFilesFilter).not.toBeInTheDocument()

      const vendorFilesFilter = canvas.queryByRole('menuitemcheckbox', {name: 'Vendored files'})
      expect(vendorFilesFilter).not.toBeInTheDocument()
    })
  },
}

export const CanSeeAllAvailableFilterOptions: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(codeownersRoute, () => {
          return HttpResponse.json(mockCodeownersData({makeViewerCodeowner: true}))
        }),
      ],
    },
  },
  render: () => (
    <FileFilter
      basePath={defaultData.basePath}
      fileFilterMenuOptions={{
        ...defaultData.fileFilterMenuOptions,
        canSeeOnlyManifestFilesFilter: true,
        canSeeVendorFilesFilter: true,
      }}
      fileFilterState={{
        ...defaultData.fileFilterState,
        fileExtensions: {
          '.js': 1,
          '.css': 2,
        },
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
      const filterButton = canvas.getByRole('button', {name: 'Filter options'})
      await userEvent.click(filterButton)

      const menu = canvas.getByRole('menu')
      expect(within(menu).getByText('File extensions')).toBeInTheDocument()
      expect(within(menu).getByRole('menuitemcheckbox', {name: '.js (1)'})).toBeInTheDocument()
      expect(within(menu).getByRole('menuitemcheckbox', {name: '.css (2)'})).toBeInTheDocument()
    })

    await step('Extra filters are visible if there are special files', async () => {
      // Wait for codeowners data to be fetched
      await waitFor(async () => {
        await expect(canvas.getByRole('menuitemradio', {name: 'Only files owned by you (1)'})).toBeInTheDocument()
      })

      const onlyManifestFilesFilter = canvas.getByRole('menuitemcheckbox', {name: 'Only manifest files'})
      expect(onlyManifestFilesFilter).toBeInTheDocument()

      const deletedFilesFilter = canvas.getByRole('menuitemcheckbox', {name: 'Deleted files'})
      expect(deletedFilesFilter).toBeInTheDocument()

      const vendorFilesFilter = canvas.getByRole('menuitemcheckbox', {name: 'Vendored files'})
      expect(vendorFilesFilter).toBeInTheDocument()
    })
  },
}

export default meta
