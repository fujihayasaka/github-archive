import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {HeaderActions} from '../HeaderActions'
import {useLoop} from '../../../hooks/queries/use-loop'
import {useLoopDraftStatus} from '../../../hooks/use-loop-draft-status'
import {useNavigate} from '@github-ui/use-navigate'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useDeleteLoop} from '../../../hooks/mutations/use-delete-loop'
import {useResetLoop} from '../../../hooks/mutations/use-reset-loop'
import {useSaveLoop} from '../../../hooks/mutations/use-save-loop'

// Mock all the hooks and utilities
jest.mock('../../../hooks/queries/use-loop')
jest.mock('../../../hooks/use-loop-draft-status')
jest.mock('../../../hooks/mutations/use-save-loop')
jest.mock('../../../hooks/mutations/use-delete-loop')
jest.mock('../../../hooks/mutations/use-reset-loop')
jest.mock('@github-ui/hydro-analytics')
jest.mock('@github-ui/use-navigate')

describe('HeaderActions', () => {
  const mockMutate = jest.fn()
  const mockNavigate = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
    ;(useSaveLoop as jest.Mock).mockReturnValue({mutate: mockMutate, isPending: false})
    ;(useDeleteLoop as jest.Mock).mockReturnValue({isPending: false})
    ;(useResetLoop as jest.Mock).mockReturnValue({mutate: mockMutate, isPending: false})
    ;(useNavigate as jest.Mock).mockReturnValue(mockNavigate)
  })

  test('should not render when no pipeline or draft exists', () => {
    ;(useLoop as jest.Mock).mockReturnValue({data: null})
    ;(useLoopDraftStatus as jest.Mock).mockReturnValue({
      hasChanges: false,
      hasPipeline: false,
      isNew: false,
    })

    render(<HeaderActions />)

    expect(screen.queryByText('Save')).not.toBeInTheDocument()
    expect(screen.queryByText('Cancel')).not.toBeInTheDocument()
    expect(screen.queryByText('Create')).not.toBeInTheDocument()
  })

  test('should render Create and Cancel buttons for new loop when only draft pipeline exists', () => {
    ;(useLoop as jest.Mock).mockReturnValue({data: {id: 'draft-pipeline-id'}})
    ;(useLoopDraftStatus as jest.Mock).mockReturnValue({
      hasChanges: false,
      hasPipeline: true,
      isNew: true,
    })

    render(<HeaderActions />)

    expect(screen.getByText('Create')).toBeInTheDocument()
    expect(screen.getByText('Cancel')).toBeInTheDocument()
    expect(screen.queryByText('Save')).not.toBeInTheDocument()
  })

  test('should render Save and Cancel buttons for existing loop with changes', () => {
    ;(useLoop as jest.Mock).mockReturnValue({data: {id: 'pipeline-id'}})
    ;(useLoopDraftStatus as jest.Mock).mockReturnValue({
      hasChanges: true,
      hasPipeline: true,
      isNew: false,
    })

    render(<HeaderActions />)

    expect(screen.getByText('Save')).toBeInTheDocument()
    expect(screen.getByText('Cancel')).toBeInTheDocument()
    expect(screen.queryByText('Create')).not.toBeInTheDocument()
  })

  test('should render Save and Cancel buttons for existing loop without changes', () => {
    ;(useLoop as jest.Mock).mockReturnValue({data: {id: 'pipeline-id'}})
    ;(useLoopDraftStatus as jest.Mock).mockReturnValue({
      hasChanges: false,
      hasPipeline: true,
      isNew: false,
    })

    render(<HeaderActions />)

    expect(screen.getByText('Save')).toBeInTheDocument()
    expect(screen.getByText('Cancel')).toBeInTheDocument()
    expect(screen.queryByText('Create')).not.toBeInTheDocument()
  })

  test('should handle save button click for existing loop', async () => {
    ;(useLoop as jest.Mock).mockReturnValue({data: {id: 'loop-id', name: 'test'}})
    ;(useLoopDraftStatus as jest.Mock).mockReturnValue({
      hasChanges: true,
      hasPipeline: true,
      isNew: false,
    })

    const {user} = render(<HeaderActions />)

    const saveButton = screen.getByText('Save')
    await user.click(saveButton)

    expect(mockMutate).toHaveBeenCalledWith('loop-id')
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.activate', {target: 'LOOP_SAVE', mode: 'loops'})
  })

  test('should handle create button click for new loop', async () => {
    ;(useLoop as jest.Mock).mockReturnValue({data: {id: 'draft-loop-id'}})
    ;(useLoopDraftStatus as jest.Mock).mockReturnValue({
      hasChanges: false,
      hasPipeline: true,
      isNew: true,
    })

    const {user} = render(<HeaderActions />)

    const createButton = screen.getByText('Create')
    await user.click(createButton)

    expect(mockMutate).toHaveBeenCalledWith('draft-loop-id')
    expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.activate', {target: 'LOOP_CREATE', mode: 'loops'})
  })
})
