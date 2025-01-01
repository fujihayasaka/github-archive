import {useAppPayload} from '@github-ui/react-core/use-app-payload'

type User = {
  avatarUrl: string
  id: string
  login: string
  name: string
  is_emu: boolean
}

export type UserHookPayload = {
  current_user: User
}

export const useUser = () => {
  const payload = useAppPayload<UserHookPayload>()
  const currentUser = payload && payload.current_user ? payload.current_user : null

  return {currentUser}
}
