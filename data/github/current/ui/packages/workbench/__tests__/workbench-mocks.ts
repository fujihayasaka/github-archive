import type {UseWorkbenchReturn} from '../hooks/use-workbench'
import type {Workbench} from '../types/workbench-types'

export const mockWorkbench: Workbench = {
  id: 'ae1ba779-b8d9-4341-8a8a-c8f32ef94930',
  name: 'New spark',
  friendlyName: 'new-spark',
  description: "it's a spark with a description", // TODO: null in prod
  runtimePermanentName: 'Fallback Name', // TODO: null in prod
  updatedAt: '2025-04-17T08:43:26.455-06:00',
  // cloudspace_id: 456, // TODO: not defined in types, returned in prod, not used in UI
  shouldGenerateInitialPrompt: true,
  previousRefinements: [],
  files: {},
  suggestions: [],
  title: 'New spark',
  billableOwner: {
    id: 42,
    login: 'monalisa',
    type: 'User',
  },
  cloudspace_id: 'cloudspace-id',
}

export const mockUseWorkbenchDataReturn: UseWorkbenchReturn = {
  id: 'test-id',
  updatedAt: new Date().toString(),
  suggestions: [],
  name: 'Workbench Name',
  friendlyName: 'workbench-name',
  description: "it's a workbench!",
  isFetching: false,
  runtimePermanentName: 'Runtime Name',
  submitPrompt: async () => ({success: true}),
  cancelPrompt: async () => undefined,
  updatePartialWorkbench: async () => mockWorkbench,
  workbench: mockWorkbench,
  persistUserEdit: async () => undefined,
  setIsMobileSidebarOpen: () => undefined,
  isMobileSidebarOpen: false,
  repositoryUrl: undefined,
  createRepository: async () => undefined,
  updateRefinementAndFiles: async () => undefined,
}
