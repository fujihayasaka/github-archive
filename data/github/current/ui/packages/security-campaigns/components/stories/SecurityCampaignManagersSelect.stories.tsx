import type {Meta} from '@storybook/react'
import {http, HttpResponse} from 'msw'
import {
  SecurityCampaignManagersSelect,
  type SecurityCampaignManagersSelectProps,
} from '../SecurityCampaignManagersSelect'
import {useState} from 'react'
import {getUser, getTeam} from '../../test-utils/mock-data'

const managers = [...Array(15).keys()].slice(1).map(id => getUser({id, login: `monalisa${id}`}))
const teamManagers = [...Array(10).keys()].slice(1).map(id => getTeam({id, slug: `manager-team${id}`}))

const SecurityCampaignManagersSelectWrapper = (args: SecurityCampaignManagersSelectProps) => {
  const [users, setUsers] = useState(args.users)
  const [teams, setTeams] = useState(args.teams)

  const onChangeUsers = (newValue: typeof users) => {
    setUsers(newValue)
    args.onChangeUsers(newValue)
  }

  const onChangeTeams = (newValue: typeof teams) => {
    setTeams(newValue)
    args.onChangeTeams(newValue)
  }

  return (
    <SecurityCampaignManagersSelect
      {...args}
      users={users}
      onChangeUsers={onChangeUsers}
      teams={teams}
      onChangeTeams={onChangeTeams}
    />
  )
}

const meta = {
  title: 'Security Campaigns Shared/Managers Select',
  component: SecurityCampaignManagersSelect,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [
        http.get('/github/security-campaigns/security/campaigns/managers', async () => {
          return HttpResponse.json({
            managers,
            teamManagers,
          })
        }),
      ],
    },
  },
  argTypes: {},
  render: (args: SecurityCampaignManagersSelectProps) => <SecurityCampaignManagersSelectWrapper {...args} />,
} satisfies Meta<typeof SecurityCampaignManagersSelect>

export default meta

const defaultArgs: Partial<SecurityCampaignManagersSelectProps> = {
  users: [],
  onChangeUsers: () => {},
  teams: [],
  onChangeTeams: () => {},
  organizationLogin: 'github',
  maxManagers: 10,
  disabled: false,
}

export const EmptySelection = {
  args: defaultArgs,
}

export const MaximumSelection = {
  args: {
    ...defaultArgs,
    users: managers.slice(0, 5),
    teams: teamManagers.slice(0, 5),
  },
}

export const DisabledSingleManagerSelection = {
  args: {
    ...defaultArgs,
    users: managers.slice(0, 1),
    disabled: true,
  },
}

export const DisabledMultipleManagersSelection = {
  args: {
    ...defaultArgs,
    users: managers.slice(0, 4),
    teams: teamManagers.slice(0, 5),
    disabled: true,
  },
}
