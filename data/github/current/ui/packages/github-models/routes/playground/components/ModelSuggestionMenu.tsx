import {NorthStarIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {PublisherAvatar} from '../../../components/PublisherAvatar'
import type {Model} from '@github-ui/marketplace-common'
import {useSearchParams} from '@github-ui/use-navigate'
import {sendEvent} from '@github-ui/hydro-analytics'
import {PlaygroundChatSuggestion} from '../../../utils/playground-types'

export function ModelSuggestionMenu({
  task,
  suggestedModels,
  action,
}: {
  task: string
  suggestedModels: Model[]
  action: string
}) {
  const [searchParam, setSearchParams] = useSearchParams()
  const handleAddModel = (m: Model) => {
    const modelName = m.name
    if (!modelName) return

    sendEvent(`${PlaygroundChatSuggestion}.${action}.clicked`)

    searchParam.set('compare_to', modelName)
    searchParam.set('resend-user-prompt', 'true')
    setSearchParams(searchParam)
  }
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <ActionList.Item>
          <ActionList.LeadingVisual>
            <NorthStarIcon />
          </ActionList.LeadingVisual>
          {task}
        </ActionList.Item>
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="medium">
        <ActionList>
          <ActionList.GroupHeading>Pick a different model</ActionList.GroupHeading>
          {suggestedModels.map(m => (
            <ActionList.Item key={m.id} onSelect={() => handleAddModel(m)}>
              <ActionList.LeadingVisual>
                <PublisherAvatar
                  logoUrl={m.logo_url}
                  darkModeIcon={m.dark_mode_icon}
                  publisher={m.publisher}
                  size={20}
                />
              </ActionList.LeadingVisual>
              {m.friendly_name}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
