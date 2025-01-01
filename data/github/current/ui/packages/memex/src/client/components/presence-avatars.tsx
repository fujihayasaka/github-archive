import {testIdProps} from '@github-ui/test-id-props'
import {createContext, memo, useContext, useMemo, useRef} from 'react'

import {getInitialState} from '../helpers/initial-state'
import {useAlivePresenceItems} from '../hooks/use-alive-presence-items'
import {useProjectState} from '../state-providers/memex/use-project-state'
import MemexAvatarStack, {itemFromPresence, type MemexAvatarStackItem} from './memex-avatar-stack'

const PresenceContext = createContext<ReadonlyArray<MemexAvatarStackItem> | null>(null)
const usePresenceUsers = () => {
  const users = useContext(PresenceContext)
  if (users == null) throw new Error('Cannot use usePresenceUsers outside of PresenceUsersProvider')
  return users
}

const defaultUserList: ReadonlyArray<MemexAvatarStackItem> = []
export const PresenceUsersProvider = memo(function PresenceUsersProvider({children}: {children: React.ReactNode}) {
  const stackRef = useRef<HTMLDivElement>(null)
  const {presenceItems, attrs} = useAlivePresenceItems(stackRef)
  const {isPublicProject} = useProjectState()

  const users = useMemo(() => {
    const {githubUrl} = getInitialState()
    if (isPublicProject || githubUrl === '') return defaultUserList
    return presenceItems
      .filter(item => !item.isOwnUser)
      .map(user =>
        itemFromPresence({
          ...user,
          avatarUrl: `${githubUrl}/user_avatars/${user.userId}`,
        }),
      )
  }, [presenceItems, isPublicProject])

  return (
    <PresenceContext.Provider value={users}>
      <span {...testIdProps('presence-avatars-listener')} {...attrs} hidden ref={stackRef} />
      {children}
    </PresenceContext.Provider>
  )
})

export const PresenceAvatars: React.FC = () => {
  const users = usePresenceUsers()
  if (users.length === 0) return null

  return (
    <div {...testIdProps('presence-avatars')}>
      <MemexAvatarStack
        items={users}
        backgroundSx={{
          backgroundColor: `canvas.subtle`,
          boxShadow: theme => `0 0 0 2px ${theme.colors.canvas.subtle} !important`,
        }}
      />
    </div>
  )
}
