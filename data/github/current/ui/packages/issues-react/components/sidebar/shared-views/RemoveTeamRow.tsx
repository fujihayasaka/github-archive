import {GitHubAvatar} from '@github-ui/github-avatar'
import {TrashIcon} from '@primer/octicons-react'
import {Box, IconButton} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import type {RemoveTeamRow$key} from './__generated__/RemoveTeamRow.graphql'

type RemoveTeamRowProps = {
  team: RemoveTeamRow$key
  onRemove: (id: string) => void
}

export const RemoveTeamRow = ({team, onRemove}: RemoveTeamRowProps) => {
  const {
    id,
    name,
    avatarUrl,
    organization: {name: orgName},
  } = useFragment(
    graphql`
      fragment RemoveTeamRow on Team {
        id
        name
        avatarUrl
        organization {
          name
        }
      }
    `,
    team,
  )
  return (
    <Box key={id} sx={{display: 'flex', justifyContent: 'space-between'}}>
      <Box key={id} sx={{display: 'flex', alignItems: 'center', gap: 1}}>
        {avatarUrl && <GitHubAvatar size={16} square src={avatarUrl} />}
        {orgName}
        <span>/</span>
        {name}
      </Box>
      <IconButton
        icon={TrashIcon}
        variant="invisible"
        aria-label={`Remove team ${orgName} ${name} from selected teams`}
        onClick={() => onRemove(id)}
      />
    </Box>
  )
}
