import type {FC} from 'react'
import {useMemo, useRef} from 'react'
import {Box, Heading, Text} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Blankslate} from '../Blankslate'
import type {BypassActor} from '@github-ui/bypass-actors/types'
import {BypassList} from '@github-ui/bypass-actors/BypassList'
import {BypassSelectPanel} from '@github-ui/bypass-actors/BypassSelectPanel'
import type {RulesetRoutePayload, RulesetTarget} from '../../types/rules-types'
import {useRelativeNavigation} from '../../hooks/use-relative-navigation'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRuleStrings} from '../../hooks/use-rule-strings'

import {capitalize} from '../../helpers/string'

export type BypassListPanelProps = {
  readOnly?: boolean
  bypassActors: BypassActor[]
  setBypassActors: (bypassActors: BypassActor[]) => void
  addBypassActor: (
    actorId: BypassActor['actorId'],
    actorType: BypassActor['actorType'],
    name: BypassActor['name'],
    bypassMode: BypassActor['bypassMode'],
    owner: BypassActor['owner'],
  ) => void
  rulesetTarget: RulesetTarget
  removeBypassActor: (bypassActor: BypassActor) => void
  updateBypassActor: (bypassActor: BypassActor) => void
}

export const BypassListPanel: FC<BypassListPanelProps> = ({
  readOnly,
  bypassActors,
  addBypassActor,
  removeBypassActor,
  rulesetTarget,
  updateBypassActor,
}: BypassListPanelProps) => {
  const {baseAvatarUrl, sourceType} = useRoutePayload<RulesetRoutePayload>()
  const {resolvePath} = useRelativeNavigation()
  const {rulesetOrPolicy} = useRuleStrings()

  const isBypassModeEnabled = rulesetTarget === 'branch'
  const bypassSuggestionsUrl = resolvePath('bypass_suggestions')

  const enabledBypassActors = useMemo(() => {
    return [
      ...bypassActors
        .filter(({_enabled}) => _enabled)
        .sort(a => (a.name === 'admin' && a.actorType === 'RepositoryRole' ? -1 : 0)),
    ]
  }, [bypassActors])

  const bypassSelectPanelAnchorRef = useRef<HTMLButtonElement>(null)

  let listName = 'bypass list'
  let bypassTitle = 'Add bypass'
  let reviewerGroup = 'roles, teams, and apps'
  if (rulesetTarget === 'repository') {
    listName = 'allow list'
    bypassTitle = 'Add actors'
  }
  if (sourceType === 'enterprise') {
    // Temporarily add 'enterprise' condition
    // until we support apps and teams at the enterprise level
    reviewerGroup = 'roles'
  }

  let subtext = `Exempt ${reviewerGroup} from this ${rulesetOrPolicy} by adding them to the ${listName}.`

  if (rulesetTarget === 'push') {
    // Temporarily add 'enterprise' condition
    // until we support apps and teams at the enterprise level
    if (sourceType === 'enterprise') {
      subtext = `Select the roles that can bypass and also approve bypass requests.`
    } else {
      subtext = `Select the roles and teams that can bypass and also approve bypass requests. Add the bots that can bypass this ${rulesetOrPolicy}.`
    }
  }
  const rulesA11y = useFeatureFlag('rules_a11y')
  return (
    <>
      <Box
        className="Box"
        sx={{
          borderTop: 0,
          borderLeft: 0,
          borderRight: 0,
          borderRadius: 0,
          pb: 2,
          display: 'flex',
          justifyContent: 'space-between',
        }}
      >
        <Heading as="h2" sx={{fontSize: 4, fontWeight: 'normal'}}>
          {capitalize(listName)}
        </Heading>
        {!readOnly && (
          <BypassSelectPanel
            title={bypassTitle}
            baseAvatarUrl={baseAvatarUrl}
            enabledBypassActors={enabledBypassActors}
            addBypassActor={addBypassActor}
            removeBypassActor={removeBypassActor}
            suggestionsUrl={bypassSuggestionsUrl}
            addReviewerSubtitle={`Choose which ${reviewerGroup} can bypass this ${rulesetOrPolicy}`}
            bypassSelectPanelAnchorRef={bypassSelectPanelAnchorRef}
            rulesA11y={rulesA11y}
          />
        )}
      </Box>
      <Text sx={{mt: 2, mb: 3, color: 'fg.muted'}}>{subtext}</Text>
      <div className="Box">
        {enabledBypassActors.length > 0 ? (
          <ul>
            <BypassList
              readOnly={readOnly}
              removeBypassActor={removeBypassActor}
              refocusOnRemoval={() =>
                setTimeout(() => {
                  bypassSelectPanelAnchorRef.current?.focus()
                })
              }
              isBypassModeEnabled={isBypassModeEnabled}
              updateBypassActor={updateBypassActor}
              enabledBypassActors={enabledBypassActors}
              baseAvatarUrl={baseAvatarUrl}
            />
          </ul>
        ) : (
          <Blankslate heading={`${capitalize(listName)} is empty`} />
        )}
      </div>
    </>
  )
}
