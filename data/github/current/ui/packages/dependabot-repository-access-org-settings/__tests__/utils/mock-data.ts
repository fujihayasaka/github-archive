import type {PickerRepository} from '@github-ui/repos-picker'
import type {DependabotRepositoryAccessOrgSettingsProps} from '../../DependabotRepositoryAccessOrgSettings'

export function getDependabotRepositoryAccessOrgSettingsProps(): DependabotRepositoryAccessOrgSettingsProps {
  return {
    allowedRepositoryPickerScope: {
      type: 'organization',
      slug: 'example-org',
    },
    allowedRepositories: [],
    accessLevel: 'public',
    setRepositoryAccessUrl: '/set-repository-access',
    setAllowedRepositoriesUrl: '/set-allowed-repositories',
  }
}

const sampleReposNames = ['smile', 'banana', 'orange'].sort()

export const sampleRepos: PickerRepository[] = sampleReposNames.map(buildRepo)

export function buildRepo(name: string, index: number): PickerRepository {
  return {
    id: index + 1,
    nodeId: `node-${index + 1}`,
    name,
    ownerLogin: 'acme',
    visibility: index % 2 === 0 ? 'internal' : 'private',
  }
}
