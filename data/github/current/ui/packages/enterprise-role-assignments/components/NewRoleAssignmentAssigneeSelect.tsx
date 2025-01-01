import {keepPreviousData, useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Button, SelectPanel} from '@primer/react'
import type {
  ActionListGroupedListProps as GroupedListProps,
  ActionListItemInput as ItemInput,
} from '@primer/react/deprecated'
import {useMemo, useState} from 'react'
import {PeopleIcon, TriangleDownIcon} from '@primer/octicons-react'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {debounce} from '@github/mini-throttle'
import type {AssigneeType} from '../enterprise-role-assignments-types'

export interface Actor {
  id: number
  name: string // handle (if user) or name (if team)
  secondaryName: string | null // name (if user, can be null) or null (if any type of team)
  avatarUrl: string
  type: AssigneeType
}

export interface SearchResult {
  users: Actor[]
  total_user_count: number
  teams: Actor[]
  total_team_count: number
}

export interface NewRoleAssignmentAssigneeSelectProps {
  assigneeId: number | null
  assigneeType: AssigneeType | null
  queryActorsPath: string
  onSelectCallback: (actor: Actor) => void
}

export function NewRoleAssignmentAssigneeSelect(props: NewRoleAssignmentAssigneeSelectProps) {
  const [open, setOpen] = useState(false)
  const [selected, setSelected] = useState<ItemInput | undefined>(undefined)
  const [filter, setFilter] = useState('')
  const debouncedSetFilter = debounce(setFilter, 250)

  const {
    data: searchResults,
    isError: queryError,
    isPending: searchQueryPending,
  } = useQuery<SearchResult>({
    queryKey: ['enterprise-role-assignments', 'actors', props.queryActorsPath, filter],
    queryFn: async () => {
      let url = props.queryActorsPath
      if (filter) {
        const searchParams = new URLSearchParams({query: filter})
        url += `?${searchParams}`
      }
      const response = await verifiedFetchJSON(url)
      if (!response.ok) {
        throw new Error(`${response.status} on ${response.url}`)
      }

      const actorsJson = await response.json()

      return {
        users: actorsJson.users,
        total_user_count: actorsJson.user_count,
        teams: actorsJson.teams,
        total_team_count: actorsJson.team_count,
      }
    },
    enabled: open,
    placeholderData: keepPreviousData,
    staleTime: Infinity,
  })

  const filteredItems = generateItemInput(searchResults)

  const groupMetadata: GroupedListProps['groupMetadata'] = useMemo(() => {
    if (searchResults) {
      return getGroupMetadata(
        searchResults.users.length,
        searchResults.total_user_count,
        searchResults.teams.length,
        searchResults.total_team_count,
        props.queryActorsPath,
      )
    }
    return [
      {groupId: 'users', header: {title: 'Users', variant: 'filled'}},
      {groupId: 'teams', header: {title: 'Enterprise Teams', variant: 'filled'}},
    ]
  }, [props.queryActorsPath, searchResults])

  if (queryError) {
    // TODO: error message (not available on v1 SelectPanel)
  }

  return (
    <SelectPanel
      title="Select user or team"
      placeholder="Select user or team"
      placeholderText="Search"
      open={open}
      onOpenChange={setOpen}
      items={filteredItems}
      onFilterChange={debouncedSetFilter}
      loading={searchQueryPending}
      selected={selected}
      onSelectedChange={onSelect}
      renderAnchor={selectProps =>
        selected ? (
          <Button leadingVisual={selected.leadingVisual} trailingVisual={TriangleDownIcon} {...selectProps}>
            {selected.description || selected.text}
          </Button>
        ) : (
          <Button leadingVisual={PeopleIcon} trailingVisual={TriangleDownIcon} {...selectProps}>
            Select user or team
          </Button>
        )
      }
      groupMetadata={groupMetadata}
      overlayProps={{width: 'medium', maxHeight: 'large', height: 'auto'}}
    />
  )

  function onSelect(itemInput: ItemInput | undefined) {
    setSelected(itemInput)
    if (itemInput?.text) {
      const selectedActor: Actor | undefined = [...(searchResults?.users || []), ...(searchResults?.teams || [])].find(
        actor => actor.id === itemInput.id,
      )
      if (selectedActor) {
        props.onSelectCallback(selectedActor)
      }
    }
  }

  function generateItemInput(unconvertedActors: SearchResult | undefined) {
    if (unconvertedActors) {
      const trailingTeamText = (actor: Actor) => {
        if (props.queryActorsPath.includes('enterprise') || actor.type === 'user') return undefined
        return actor.type === 'businessteam' ? 'Enterprise team' : 'Org team'
      }
      const allActors: ItemInput[] = [...unconvertedActors.users, ...unconvertedActors.teams].map((actor: Actor) => ({
        id: actor.id,
        text: actor.name,
        key: actor.id,
        description: actor.secondaryName || undefined,
        trailingText: trailingTeamText(actor),
        leadingVisual: () => <GitHubAvatar src={actor.avatarUrl} square={actor.type !== 'user'} />,
        groupId: actor.type === 'user' ? 'users' : 'teams',
      }))

      return allActors
    }

    return []
  }
}

function getGroupMetadata(
  current_user_count: number,
  total_user_count: number,
  current_team_count: number,
  total_team_count: number,
  queryActorsPath: string,
) {
  const newHeaderMetadata: GroupedListProps['groupMetadata'] = []
  if (total_user_count > 0) {
    const displayed_users_count = current_user_count > total_user_count ? total_user_count : current_user_count
    newHeaderMetadata.push({
      groupId: 'users',
      header: {title: `Users ${displayed_users_count} of ${total_user_count}`, variant: 'filled'},
    })
  } else {
    newHeaderMetadata.push({
      groupId: 'users',
    })
  }
  if (total_team_count > 0) {
    const displayed_teams_count = current_team_count > total_team_count ? total_team_count : current_team_count
    newHeaderMetadata.push({
      groupId: 'teams',
      header: {
        title: queryActorsPath.includes('enterprise')
          ? `Enterprise teams ${displayed_teams_count} of ${total_team_count}`
          : `Teams ${displayed_teams_count} of ${total_team_count}`,
        variant: 'filled',
      },
    })
  } else {
    newHeaderMetadata.push({
      groupId: 'teams',
    })
  }
  return newHeaderMetadata
}
