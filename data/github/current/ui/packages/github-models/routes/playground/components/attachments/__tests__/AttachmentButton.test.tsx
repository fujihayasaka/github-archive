import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {within} from '@testing-library/react'
import {AttachmentButton} from '../AttachmentButton'
import {AttachmentsProvider} from '@github-ui/attachments'
import {MockFileAttachment, testFile} from '@github-ui/attachments/test-utils'

const sendAnalyticsEvent = jest.fn().mockName('sendAnalyticsEvent')

jest.mock('@github-ui/use-analytics', () => ({
  useAnalytics: () => ({sendAnalyticsEvent}),
}))

const useCreateAttachmentCallback = jest
  .fn((file: File) => new MockFileAttachment(file))
  .mockName('useCreateAttachment#callback')

jest.mock('../use-create-attachment', () => ({
  useCreateAttachment() {
    return useCreateAttachmentCallback
  },
}))

beforeEach(() => {
  jest.clearAllMocks()
})

describe('AttachmentButton', () => {
  test('renders with enabled button', async () => {
    const {container, user} = render(<AttachmentButton />)

    const button = within(container).getByRole('button', {name: 'Attach an image'})
    expect(button).toBeInTheDocument()
    expect(button).toBeEnabled()

    await user.click(button)

    expect(sendAnalyticsEvent).not.toHaveBeenCalled()
  })

  test('renders with disabled button', () => {
    const {container} = render(<AttachmentButton disabled />)

    const button = within(container).getByRole('button', {name: 'Attach an image'})
    expect(button).toBeInTheDocument()
    expect(button).toBeDisabled()
    expect(sendAnalyticsEvent).not.toHaveBeenCalled()
  })

  test('does not allow multiple if the limit is less than 2', async () => {
    const {container} = render(<AttachmentButton />, 1)

    const input = getFilePickerElement(container)
    expect(input.hasAttribute('multiple')).toBe(false)
  })

  test('allows multiple if the limit is greater than 1', async () => {
    const {container} = render(<AttachmentButton />, 2)

    const input = getFilePickerElement(container)
    expect(input.hasAttribute('multiple')).toBe(true)
  })

  test('calls the useCreateAttachment hook when a file is chosen', async () => {
    const {container, user} = render(<AttachmentButton />)
    const input = getFilePickerElement(container)
    await user.upload(input, testFile())

    expect(useCreateAttachmentCallback).toHaveBeenCalledTimes(1)
  })
})

function render(component: JSX.Element, limit?: number) {
  return htmlRender(<AttachmentsProvider attachLimit={limit}>{component}</AttachmentsProvider>)
}

function getFilePickerElement(container: HTMLElement) {
  // For this very unique case, we need to bypass the linter. Because this is an invisible element,
  // but we need to check for specific attributes that prompt behaviors in the operating system.
  // eslint-disable-next-line testing-library/no-container, testing-library/no-node-access
  const input = container.getElementsByTagName('input')[0]
  expect(input).toBeInstanceOf(HTMLInputElement)
  expect(input!.getAttribute('type')).toBe('file')
  return input!
}
