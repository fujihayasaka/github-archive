import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {ToolsIcon} from '@primer/octicons-react'
import {dummyPipelines} from '../../example-loops/dummy-pipelines'
import {useNavigate} from 'react-router-dom'
import {useLoop} from '../../hooks/queries/use-loop'

export function DevelopmentButton() {
  const {data: loop} = useLoop()
  const pipelines = dummyPipelines
  const currentPipelineId = loop?.id
  const navigate = useNavigate()

  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>
          <IconButton aria-label="Development" icon={ToolsIcon} />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" role="menu">
            {Object.values(pipelines).map(pipe => (
              <ActionList.Item
                key={pipe.id}
                value={pipe.id}
                selected={currentPipelineId === pipe.id}
                onSelect={() => navigate(`/copilot/l/${pipe.id}`)}
              >
                {pipe.title}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
}
