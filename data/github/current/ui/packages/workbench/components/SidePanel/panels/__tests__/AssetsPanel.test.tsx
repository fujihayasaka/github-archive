import {mockClientEnv} from '@github-ui/client-env/mock'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {screen} from '@testing-library/react'

import {renderWorkbenchStore, type WorkbenchStoreProps} from '../../../../__tests__/WorkbenchStoreWrapper'
import {useFilesContext} from '../../../../contexts/FilesContext'
import {useFileSyncerContext} from '../../../../contexts/FileSyncerContext'
import {WorkbenchUIContextProvider} from '../../../../contexts/WorkbenchUIContext'
import {AssetsPanel} from '../AssetsPanel'

// Mock dependencies
jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn(),
}))

// Default mock values
const defaultWorkbenchData = {
  id: 'test-workbench-id',
  name: 'Test Workbench',
  description: 'Test Description',
  deployUrl: 'https://test-deploy-url',
  repositoryUrl: 'https://github.com/test-repo',
  runtimePermanentName: 'test-runtime',
  friendlyName: 'Test Friendly Name',
}

jest.mock('../../../../contexts/FilesContext', () => ({
  useFilesContext: jest.fn(),
}))

jest.mock('../../../../contexts/FileSyncerContext', () => ({
  useFileSyncerContext: jest.fn(),
}))

jest.mock('../../../../contexts/WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn(() => ({
    sparkFileUrl: jest.fn(),
  })),
  sparkPathRegex: /.*\.spark$/,
}))

// Default mocks setup
jest.mocked(useRoutePayload).mockReturnValue({
  workbench: defaultWorkbenchData,
})

const renderAssetsPanel = (props: WorkbenchStoreProps = {}) => {
  return renderWorkbenchStore({
    children: (
      <WorkbenchUIContextProvider>
        <AssetsPanel />
      </WorkbenchUIContextProvider>
    ),
    ...props,
  })
}

const mockUseFilesContext = useFilesContext as jest.Mock
const mockUseFileSyncerContext = useFileSyncerContext as jest.Mock

describe('AssetsPanel', () => {
  beforeEach(() => {
    jest.clearAllMocks()

    mockUseFilesContext.mockReturnValue({
      getFileList: jest.fn().mockReturnValue([]),
    })

    mockUseFileSyncerContext.mockReturnValue({
      getFileSyncerV2: jest.fn(),
      forceFileTreeRefresh: jest.fn(),
      fileSyncerStarted: false,
    })
  })

  it('should render with default props', () => {
    renderAssetsPanel()

    expect(screen.getByRole('button', {name: 'Upload file'})).toBeInTheDocument()
  })

  it('should render with inputs enabled if globalReadOnly without FF', () => {
    renderAssetsPanel({readOnly: true})

    expect(screen.getByRole('button', {name: 'Upload file'})).not.toBeDisabled()
  })

  it('should render with inputs disabled if globalReadOnly with FF', () => {
    mockClientEnv({
      featureFlags: ['workbench_store_readonly'],
    })

    renderAssetsPanel({readOnly: true})

    expect(screen.getByRole('button', {name: 'Upload file'})).toBeDisabled()
  })

  it('should render with inputs disabled if fileSyncer is disconnected', () => {
    mockClientEnv({
      featureFlags: ['workbench_store_readonly'],
    })

    renderAssetsPanel({readOnly: false, status: {fileSyncer: 'disconnected'}})

    expect(screen.getByRole('button', {name: 'Upload file'})).toBeDisabled()
  })
})
