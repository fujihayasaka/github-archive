import {GitHubAvatar} from '@github-ui/github-avatar'
import {Stack, ActionMenu, ActionList, Truncate} from '@primer/react'
import {AccountButtonAvatar} from '../AccountButtonAvatar'
import {usePlanForm} from './PlanFormContext'

export default function PlanFormAccountSelector() {
  const {listing, planInfo, selectedAccount, setSelectedAccount} = usePlanForm()

  const accounts = []
  if (planInfo.currentUser) {
    accounts.push({
      displayLogin: planInfo.currentUser.displayLogin,
      hasExtensibilityAccess: planInfo.currentUser.hasExtensibilityAccess,
      image: planInfo.currentUser.image,
      label: 'Personal account',
    })
  }
  for (const org of planInfo.organizations) {
    accounts.push({
      displayLogin: org.displayLogin,
      hasExtensibilityAccess: org.hasExtensibilityAccess,
      image: org.image,
      label: org.isEnterpriseOwned ? 'Enterprise owned organization' : 'Organization',
    })
  }

  return (
    selectedAccount && (
      <>
        {planInfo.organizations.length === 0 ? (
          <input type="hidden" name="account" id="account" value={selectedAccount} />
        ) : (
          <Stack direction="horizontal" gap="condensed" align="center">
            <div className="text-bold">Account:</div>
            <ActionMenu>
              <ActionMenu.Button leadingVisual={<AccountButtonAvatar planInfo={planInfo} account={selectedAccount} />}>
                {selectedAccount || 'Select account'}
              </ActionMenu.Button>
              <ActionMenu.Overlay maxHeight="large" width="medium" className="overflow-auto">
                <ActionList>
                  {accounts.map(account => (
                    <ActionList.Item
                      key={account.displayLogin}
                      onSelect={() => setSelectedAccount(account.displayLogin)}
                    >
                      <ActionList.LeadingVisual>
                        {account.image && <GitHubAvatar square src={account.image} />}
                      </ActionList.LeadingVisual>
                      <Stack gap="condensed" direction="horizontal" align="center">
                        <div className="text-bold flex-shrink-0">{account.displayLogin}</div>
                        <Truncate
                          inline
                          title={account.label}
                          className="width-fit fgColor-muted text-normal text-small"
                        >
                          {account.label}
                        </Truncate>
                      </Stack>
                      {listing.copilotApp && account.hasExtensibilityAccess && (
                        <ActionList.Description variant="block" className="fgColor-attention">
                          Supports Copilot extensions
                        </ActionList.Description>
                      )}
                    </ActionList.Item>
                  ))}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
            {selectedAccount && <input type="hidden" name="account" id="account" value={selectedAccount} />}
          </Stack>
        )}
      </>
    )
  )
}
