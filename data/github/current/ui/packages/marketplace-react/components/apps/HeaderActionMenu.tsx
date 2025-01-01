import {ActionList, ActionMenu, IconButton, useResponsiveValue} from '@primer/react'
import {GearIcon, KebabHorizontalIcon, PencilIcon} from '@primer/octicons-react'
import type {AppListing} from '@github-ui/marketplace-common'
import type {PlanInfo} from '../../types'

interface HeaderActionMenuProps {
  app: AppListing
  planInfo: PlanInfo
  userCanEdit: boolean
}

export function HeaderActionMenu(props: HeaderActionMenuProps) {
  const {app, planInfo, userCanEdit} = props
  const showHeaderActionMenu =
    planInfo.viewerHasPurchased || planInfo.anyOrgsPurchased || planInfo.installedForViewer || userCanEdit
  const anyPlansExist = planInfo.viewerHasPurchased || planInfo.anyOrgsPurchased
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean

  return (
    showHeaderActionMenu && (
      <div data-testid="listing-actions">
        <ActionMenu>
          <ActionMenu.Anchor>
            <IconButton
              icon={KebabHorizontalIcon}
              aria-label="More actions"
              data-testid="listing-actions-button"
              size={isMobile ? 'medium' : 'large'}
            />
          </ActionMenu.Anchor>

          <ActionMenu.Overlay width="small" align="end">
            <ActionList>
              {anyPlansExist && (
                <ActionList.Group>
                  <ActionList.GroupHeading>Edit current plan</ActionList.GroupHeading>
                  {planInfo.viewerHasPurchased && planInfo.currentUser && (
                    <ActionList.LinkItem
                      href={`/marketplace/${app.slug}/order/${
                        planInfo.planIdByLogin[planInfo.currentUser.displayLogin]
                      }?account=${planInfo.currentUser.displayLogin}`}
                    >
                      {planInfo.currentUser.displayLogin}
                    </ActionList.LinkItem>
                  )}
                  {planInfo.viewerBilledOrganizations.map(orgName => (
                    <ActionList.LinkItem
                      key={orgName}
                      href={`/marketplace/${app.slug}/order/${planInfo.planIdByLogin[orgName]}?account=${orgName}`}
                    >
                      {orgName}
                    </ActionList.LinkItem>
                  ))}
                </ActionList.Group>
              )}

              {anyPlansExist && (planInfo.installedForViewer || userCanEdit) && <ActionList.Divider />}

              {planInfo.installedForViewer && (
                <ActionList.LinkItem href="/settings/installations">
                  <ActionList.LeadingVisual>
                    <GearIcon />
                  </ActionList.LeadingVisual>
                  Configure account access
                </ActionList.LinkItem>
              )}
              {userCanEdit && (
                <ActionList.LinkItem href={`/marketplace/${app.slug}/edit`}>
                  <ActionList.LeadingVisual>
                    <PencilIcon />
                  </ActionList.LeadingVisual>
                  Manage app listing
                </ActionList.LinkItem>
              )}
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </div>
    )
  )
}
