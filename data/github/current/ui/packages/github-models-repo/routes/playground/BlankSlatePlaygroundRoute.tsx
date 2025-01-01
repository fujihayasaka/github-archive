import {ModelsRepoLayout} from '../../components/ModelsRepoLayout'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {Repository} from '@github-ui/current-repository'
import {useState} from 'react'
import {Blankslate} from '@primer/react/experimental'
import {AlertIcon, SidebarCollapseIcon} from '@primer/octicons-react'
import {modelsPlaygroundPath} from '@github-ui/paths'
import {IconButton} from '@primer/react'

export function BlankSlatePlaygroundRoute() {
  const [fileTreeExpanded, setFileTreeExpanded] = useState(true)
  const {repository} = useAppPayload<{repository: Repository}>()

  if (!repository) return null

  return (
    <div className="position-relative">
      <ModelsRepoLayout fileTreeExpanded={fileTreeExpanded} setFileTreeExpanded={setFileTreeExpanded}>
        {!fileTreeExpanded && (
          <IconButton
            onClick={() => setFileTreeExpanded(true)}
            aria-label="Expand menu"
            icon={SidebarCollapseIcon}
            variant="invisible"
            className="position-absolute top-0 left-0 mt-5 ml-3"
          />
        )}
        <Blankslate>
          <Blankslate.Visual>
            <AlertIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Heading>No models are available in the playground.</Blankslate.Heading>
          <Blankslate.Description>
            Please reach out to your organization administrator to enable models.
          </Blankslate.Description>
          <Blankslate.SecondaryAction href={modelsPlaygroundPath()}>
            Try the Models Playground in GitHub Marketplace.
          </Blankslate.SecondaryAction>
        </Blankslate>
      </ModelsRepoLayout>
    </div>
  )
}
