import {useState, useEffect} from 'react'
import {Portal} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {BypassAvatar} from './BypassActor'
import {getApprovers} from '../services/api'
import type {AppPayload, BypassActor as BypassActorType} from '../delegated-bypass-types'
import {humanizeRoleName} from '../helpers/humanize-role-name'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import styles from './ApproversListDialog.module.css'

const subtitle = 'Roles and teams who can approve requests for bypass privileges'

type ApproversListDialogProps = {
  onClose: () => void
  rulesetId?: number
}

export default function ApproversListDialog({onClose, rulesetId}: ApproversListDialogProps) {
  const [approvers, setApprovers] = useState<BypassActorType[]>([])
  const {base_avatar_url: baseAvatarUrl} = useAppPayload<AppPayload>()

  useEffect(() => {
    const fetch = async () => {
      const {approvers: data, statusCode} = await getApprovers(`${ssrSafeLocation.pathname}/approvers`, {rulesetId})
      if (statusCode === 200) {
        setApprovers(data)
      }
    }
    fetch()
  }, [rulesetId])

  return (
    <Portal>
      <Dialog title="Approvers" subtitle={subtitle} onClose={onClose}>
        <ul className={`d-flex flex-column list-style-none mx-1 my-2 ${styles.approversList}`}>
          {approvers.map(({actorType, actorId, name}) => (
            <li className="d-flex flex-row flex-items-center gap-2 py-1" key={`${actorType}-${actorId}`}>
              <BypassAvatar type={actorType} id={actorId} name={name} baseUrl={baseAvatarUrl} size={20} />
              <span className="width-full py-1">{humanizeRoleName({actorType, name})}</span>
            </li>
          ))}
        </ul>
      </Dialog>
    </Portal>
  )
}
