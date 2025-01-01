import {GitHubAvatar} from '@github-ui/github-avatar'
import {Link, ActionMenu, ActionList} from '@primer/react'
import {orgHovercardPath} from '@github-ui/paths'
import type {Org} from '../types'

import styles from './OrgItem.module.css'

const EnablementMenu = ({
  enabled,
  updateOrgEnablement,
  disableForm,
}: {
  enabled: boolean
  updateOrgEnablement: (enablement: string) => void
  disableForm: boolean
}) => {
  return (
    <ActionMenu>
      <ActionMenu.Button>{enabled ? 'Enabled' : 'Disabled'}</ActionMenu.Button>

      <ActionMenu.Overlay>
        <ActionList selectionVariant="single">
          <ActionList.Item
            onSelect={() => updateOrgEnablement('enable')}
            selected={enabled}
            disabled={disableForm}
            data-testid="org-item-enable-menu"
          >
            Enabled
          </ActionList.Item>
          <ActionList.Item onSelect={() => updateOrgEnablement('disable')} selected={!enabled}>
            Disabled
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

export function OrgItem({
  org,
  enabled,
  updateOrgEnablement,
  disableForm,
  checked,
  handleCheckClick,
}: {
  org: Org
  enabled: boolean
  updateOrgEnablement: (enablement: string) => void
  disableForm: boolean
  checked: boolean
  handleCheckClick: (id: number) => void
}) {
  const pluralize = (count: number, noun: string, suffix = 's') => `${count} ${noun}${count !== 1 ? suffix : ''}`

  return (
    <div className="d-flex flex-justify-between flex-items-center" data-testid="org-item">
      <div>
        <div className="d-flex flex-items-center">
          <input
            type="checkbox"
            name="organizations[]"
            value={org.id}
            aria-label="Member"
            className="mr-3"
            checked={checked}
            onChange={() => handleCheckClick(org.id)}
            data-testid="org-item-checkbox"
          />
          <div className={styles.Box}>
            <Link href={org.path}>
              <GitHubAvatar
                src={org.avatarUrl}
                size={32}
                data-hovercard-url={orgHovercardPath({owner: org.displayLogin})}
                square
                className={styles.GitHubAvatar}
              />
            </Link>
            <div>
              <div>
                <Link href={org.path}>{org.displayLogin}</Link>
              </div>
              <div>
                <span className="color-fg-muted text-small">{pluralize(org.memberCount, 'member')}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
      <EnablementMenu enabled={enabled} updateOrgEnablement={updateOrgEnablement} disableForm={disableForm} />
    </div>
  )
}
