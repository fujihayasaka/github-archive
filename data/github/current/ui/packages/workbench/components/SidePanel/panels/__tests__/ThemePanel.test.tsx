import {mockClientEnv} from '@github-ui/client-env/mock'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {screen} from '@testing-library/react'

import {renderWorkbenchStore, type WorkbenchStoreProps} from '../../../../__tests__/WorkbenchStoreWrapper'
import {WorkbenchUIContextProvider} from '../../../../contexts/WorkbenchUIContext'
import {Service, Status} from '../../../../utilities/workbench-store-reducer'
import {ThemePanel} from '../ThemePanel'

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

jest.mock('../../../../contexts/TargetedEditsContext', () => ({
  useTargetedEditsContext: () => ({
    selectedElement: null,
    targetedEditsEnabled: false,
    disableTargetedEdits: jest.fn(),
    deselectElement: jest.fn(),
    themeVariables: {
      accent: '#000',
      'accent-foreground': '#000',
      background: '#000',
      border: '#000',
      card: '#000',
      'card-foreground': '#000',
      destructive: '#000',
      'destructive-foreground': '#000',
      foreground: '#000',
      input: '#000',
      muted: '#000',
      'muted-foreground': '#000',
      popover: '#000',
      'popover-foreground': '#000',
      primary: '#000',
      'primary-foreground': '#000',
      ring: '#000',
      secondary: '#000',
      'secondary-foreground': '#000',
      radius: '#000',
      spacing: '#000',
    },
    refetchThemeVariables: jest.fn(),
  }),
}))

jest.mock('../../../../contexts/WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn(() => ({
    sparkFileUrl: jest.fn(),
  })),
  sparkPathRegex: /.*\.spark$/,
}))

jest.mock('../../../../contexts/FileSyncerContext', () => ({
  useFileSyncerContext: jest.fn(() => ({
    fileChangeStack: [],
  })),
}))

// Default mocks setup
jest.mocked(useRoutePayload).mockReturnValue({
  workbench: defaultWorkbenchData,
})

const renderThemePanel = (props: WorkbenchStoreProps = {}) => {
  return renderWorkbenchStore({
    children: (
      <WorkbenchUIContextProvider>
        <ThemePanel />
      </WorkbenchUIContextProvider>
    ),
    ...props,
  })
}

describe('ThemePanel', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('should render with default props', () => {
    mockClientEnv({
      featureFlags: ['workbench_store_readonly'],
    })
    renderThemePanel()

    // Color pickers for accents
    for (const picker of screen.getAllByLabelText('Color picker')) {
      expect(picker).toBeInTheDocument()
    }

    // Border radius controls
    // expect(screen.getByRole('button', {name: 'None'})).toBeInTheDocument()
    // expect(screen.getByRole('button', {name: 'Small'})).toBeInTheDocument()
    // expect(screen.getByRole('button', {name: 'Medium'})).toBeInTheDocument()
    // expect(screen.getByRole('button', {name: 'Large'})).toBeInTheDocument()
    // expect(screen.getByRole('button', {name: 'Full'})).toBeInTheDocument()
  })

  it('should render with inputs disabled if globalReadOnly with FF', () => {
    mockClientEnv({
      featureFlags: ['workbench_store_readonly'],
    })

    renderThemePanel({readOnly: true})

    // Color pickers should be disabled
    for (const picker of screen.getAllByLabelText('Color picker')) {
      expect(picker).toBeDisabled()
    }

    // Border radius controls should be disabled
    // expect(screen.getByRole('button', {name: 'None'})).toBeDisabled()
    // expect(screen.getByRole('button', {name: 'Small'})).toBeDisabled()
    // expect(screen.getByRole('button', {name: 'Medium'})).toBeDisabled()
    // expect(screen.getByRole('button', {name: 'Large'})).toBeDisabled()
    // expect(screen.getByRole('button', {name: 'Full'})).toBeDisabled()
  })

  it('should render with inputs disabled if fileSyncer is disconnected', () => {
    mockClientEnv({
      featureFlags: ['workbench_store_readonly'],
    })

    renderThemePanel({readOnly: false, status: {[Service.FILE_SYNCER]: Status.DISCONNECTED}})

    // Color pickers should be disabled
    for (const picker of screen.getAllByLabelText('Color picker')) {
      expect(picker).toBeDisabled()
    }

    // Border radius controls should be disabled
    // expect(screen.getByRole('button', {name: 'None'})).toBeDisabled()
    // expect(screen.getByRole('button', {name: 'Small'})).toBeDisabled()
    // expect(screen.getByRole('button', {name: 'Medium'})).toBeDisabled()
    // expect(screen.getByRole('button', {name: 'Large'})).toBeDisabled()
    // expect(screen.getByRole('button', {name: 'Full'})).toBeDisabled()
  })

  describe('without FF enabled', () => {
    it('should render with inputs enabled if globalReadOnly without FF', () => {
      renderThemePanel({readOnly: true})

      // Color pickers should be enabled
      for (const picker of screen.getAllByLabelText('Color picker')) {
        expect(picker).not.toBeDisabled()
      }

      // Border radius controls should be enabled
      // expect(screen.getByRole('button', {name: 'None'})).not.toBeDisabled()
      // expect(screen.getByRole('button', {name: 'Small'})).not.toBeDisabled()
      // expect(screen.getByRole('button', {name: 'Medium'})).not.toBeDisabled()
      // expect(screen.getByRole('button', {name: 'Large'})).not.toBeDisabled()
      // expect(screen.getByRole('button', {name: 'Full'})).not.toBeDisabled()
    })
  })
})
