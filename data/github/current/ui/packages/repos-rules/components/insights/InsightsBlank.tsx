import {ClockIcon, PulseIcon} from '@primer/octicons-react'
import {Octicon} from '@primer/react/deprecated'
import {useRelativeNavigation} from '../../hooks/use-relative-navigation'
import {RulesetEnforcement} from '../../types/rules-types'
import {NewRulesetButton} from '../NewRulesetButton'
import type {FlashAlert} from '@github-ui/dismissible-flash'

import styles from './InsightsBlank.module.css'

export function InsightsBlank({
  showCreateButton,
  timedOut,
  setFlashAlert,
}: {
  showCreateButton: boolean
  timedOut?: boolean
  setFlashAlert: (flashAlert: FlashAlert) => void
}) {
  const {resolvePath} = useRelativeNavigation()

  return (
    <div className="blankslate">
      <Octicon icon={timedOut ? ClockIcon : PulseIcon} size={24} />
      <h2 className="blankslate-heading">
        {timedOut ? 'Rule insights search timed out' : 'No rule evaluations matched your search'}
      </h2>
      {timedOut ? (
        <p>Try adjusting your filters or reducing the time range of your search</p>
      ) : showCreateButton ? (
        <>
          <p>Try expanding your search or creating a new ruleset in evaluate mode</p>
          <NewRulesetButton
            rulesetsUrl={resolvePath('../')}
            reloadDocument
            defaultEnforcement={RulesetEnforcement.Evaluate}
            setFlashAlert={setFlashAlert}
            className={styles.NewRulesetButton}
          />
        </>
      ) : null}
    </div>
  )
}
