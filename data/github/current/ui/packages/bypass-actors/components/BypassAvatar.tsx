import {GitHubAvatar} from '@github-ui/github-avatar'
import type {FC} from 'react'
import {Octicon} from '@primer/react/deprecated'
import {EyeIcon, PencilIcon, PersonIcon, PeopleIcon, ToolsIcon, type Icon, KeyIcon} from '@primer/octicons-react'
import type {BypassActorType} from '../bypass-actors-types'

import styles from './BypassAvatar.module.css'

const roleIconMap: {[key: string]: Icon} = {
  Write: PencilIcon,
  Maintain: ToolsIcon,
  'Repository admin': EyeIcon,
  'Organization admin': EyeIcon,
}

export const BypassAvatar: FC<{
  baseUrl: string
  id: string | number | null
  name: string
  type: BypassActorType
  size?: number
}> = ({baseUrl, id, type, name, size = 16}) => {
  if (type === 'Team') {
    return <GitHubAvatar alt={name} src={`${baseUrl}/t/${id}`} size={size} />
  }
  if (type === 'Integration') {
    return <GitHubAvatar alt={name} src={`${baseUrl}/in/${id}`} size={size} />
  }
  if (type === 'RepositoryRole' || type === 'OrganizationAdmin') {
    return <Octicon icon={roleIconMap[name] || PersonIcon} className={styles.Octicon} />
  }
  if (type === 'DeployKey') {
    return <Octicon icon={KeyIcon} className={styles.Octicon} />
  }
  if (type === 'EnterpriseTeam') {
    return <Octicon icon={PeopleIcon} className={styles.Octicon} />
  }
  if (type === 'EnterpriseOwner') {
    return <Octicon icon={PeopleIcon} className={styles.Octicon} />
  }
  return null
}
