import {ModelsRepoLayout} from '../../components/ModelsRepoLayout'
import {ModelsPlaygroundComponent} from '@github-ui/github-models/ModelsPlaygroundRoute'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {Repository} from '@github-ui/current-repository'
import {useState} from 'react'
import type {GettingStartedPayload} from '@github-ui/github-models'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useFilteredModels} from '../../hooks/use-filtered-models'

export function PlaygroundRoute() {
  const [fileTreeExpanded, setFileTreeExpanded] = useState(true)
  const {repository} = useAppPayload<{repository: Repository}>()
  const {restrictedModels} = useRoutePayload<GettingStartedPayload>()

  const {availableModels, isLoadingModels} = useFilteredModels(repository.ownerLogin, repository.name, restrictedModels)

  if (!repository) return

  return (
    <ModelsRepoLayout width="full" fileTreeExpanded={fileTreeExpanded} setFileTreeExpanded={setFileTreeExpanded}>
      <ModelsPlaygroundComponent
        repository={{ownerLogin: repository.ownerLogin, name: repository.name}}
        fileTreeExpanded={fileTreeExpanded}
        setFileTreeExpanded={setFileTreeExpanded}
        availableModels={availableModels}
        isLoadingModels={isLoadingModels}
      />
    </ModelsRepoLayout>
  )
}
