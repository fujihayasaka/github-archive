import {Button} from '@primer/react'
import {useNavigate} from '@github-ui/use-navigate'
import {repoPromptNewPath, type Repository} from '@github-ui/paths'
import type {ModelState} from '../../../types'

export function CreatePromptFileButton({modelState, repository}: {modelState: ModelState; repository: Repository}) {
  const navigate = useNavigate()

  const handleCreatePromptFile = () => {
    navigate(repoPromptNewPath(repository), {
      state: {
        params: modelState.parameters,
        model: modelState.catalogData.original_name,
        systemPrompt: modelState.systemPrompt,
      },
    })
  }

  return (
    <>
      <span className="text-small color-fg-muted">Evaluate, test, and share parameters</span>
      <Button onClick={handleCreatePromptFile}>Create prompt.yml file</Button>
    </>
  )
}
