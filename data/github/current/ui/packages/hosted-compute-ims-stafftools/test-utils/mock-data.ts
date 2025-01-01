import type {MainPayload} from '../routes/Main'
import type {ListImageVersionsPayload} from '../routes/ListImageVersions'

export function getMainRoutePayload(): MainPayload {
  return {
    imageDefinitions: [
      {
        id: 1,
        name: 'test-name-1',
        osType: 'Linux',
        architecture: 'X64',
        enabled: false,
        pointsToImageDefinitionId: 0,
        createdAt: '',
        updatedAt: '',
        imageVersionsCount: 0,
        featureFlag: '',
      },
      {
        id: 2,
        name: 'test-name-2',
        osType: 'Windows',
        architecture: 'Arm64',
        enabled: false,
        pointsToImageDefinitionId: 0,
        createdAt: '',
        updatedAt: '',
        imageVersionsCount: 0,
        featureFlag: '',
      },
      {
        id: 3,
        name: 'test-name',
        osType: 'Linux',
        architecture: 'Arm64',
        enabled: false,
        pointsToImageDefinitionId: 0,
        createdAt: '',
        updatedAt: '',
        imageVersionsCount: 0,
        featureFlag: 'test-ff',
      },
      {
        id: 4,
        name: 'test-name',
        osType: 'Linux',
        architecture: 'Arm64',
        enabled: false,
        pointsToImageDefinitionId: 3,
        createdAt: '',
        updatedAt: '',
        imageVersionsCount: 0,
        featureFlag: '',
      },
    ],
  }
}

export function getListImageVersionsRoutePayload(): ListImageVersionsPayload {
  return {
    imageDefinition: {
      id: 1,
      name: 'test-name-1',
      osType: 'Linux',
      architecture: 'X64',
      enabled: false,
      pointsToImageDefinitionId: 0,
      createdAt: '',
      updatedAt: '',
      imageVersionsCount: 1,
      featureFlag: '',
    },
    imageVersions: [
      {
        id: 1,
        imageDefinitionId: 1,
        version: '1.0.0',
        state: 'Ready',
        stateDetails: '',
        sizeGb: 0,
        enabled: false,
        createdAt: '',
        updatedAt: '',
        isLatest: false,
      },
    ],
  }
}
