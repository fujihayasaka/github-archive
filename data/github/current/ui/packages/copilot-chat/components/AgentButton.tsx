import {MentionIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useState} from 'react'

import {useAvailableAgents, useInsertAgent, type UseInsertAgentProps} from '../utils/agents-helpers'
import {AgentsNotSupportedDialog, NoAgentsAvailableDialog} from './AgentsDialogs'

// eslint-disable-next-line @typescript-eslint/no-empty-object-type
interface AgentButtonProps extends UseInsertAgentProps {}

export function AgentButton(props: AgentButtonProps) {
  const {disabled, loading, imperativelyFetch} = useAvailableAgents(false)
  const insertAgent = useInsertAgent(props)

  const [dialog, setDialog] = useState<null | 'disabled' | 'noAgentsAvailable'>(null)

  const onClick = async () => {
    if (disabled) return setDialog('disabled')

    const data = await imperativelyFetch()
    if (!data || data.agents.length === 0) return setDialog('noAgentsAvailable')

    insertAgent()
  }

  return (
    <>
      <IconButton
        icon={MentionIcon}
        onClick={onClick}
        onMouseDown={e => e.preventDefault()}
        size="small"
        aria-label="Add an extension"
        variant="invisible"
        className="fgColor-muted"
        loading={loading}
      />
      {dialog === 'disabled' && <AgentsNotSupportedDialog onClose={() => setDialog(null)} />}
      {dialog === 'noAgentsAvailable' && <NoAgentsAvailableDialog onClose={() => setDialog(null)} />}
    </>
  )
}
