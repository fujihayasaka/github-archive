import type {Suggestion, Suggestions} from '@github-ui/inline-autocomplete/types'
import {useMemo} from 'react'

import type {CopilotChatOrg} from '../../utils/copilot-chat-types'
import {useChatState} from '../../utils/CopilotChatContext'
import {SSOOrgSuggestion} from './SSOOrgSuggestion'

export interface SSOOrgsQuery {
  category: 'sso-orgs'
  filter: string
}

export const ssoUrl = (org: CopilotChatOrg) =>
  `/orgs/${encodeURIComponent(org.login)}/sso?return_to=${encodeURIComponent(location.href)}`

export function useSSOOrgsSuggestions(query: SSOOrgsQuery | null) {
  const {ssoOrganizations} = useChatState()

  return useMemo<Suggestions | null>(() => {
    if (!query) return null

    return ssoOrganizations
      .filter(org => org.login.toLowerCase().includes(query.filter.toLowerCase()))
      .slice(0, 10)
      .map<Suggestion>(org => ({
        value: null,
        key: `open-link:${ssoUrl(org)}`,
        render: props => <SSOOrgSuggestion org={org} {...props} />,
      }))
  }, [query, ssoOrganizations])
}
