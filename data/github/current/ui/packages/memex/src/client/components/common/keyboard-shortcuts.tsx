import {KeybindingHint} from '@primer/react/experimental'

import {areCharacterKeyShortcutsDisabled} from '../../helpers/keyboard-shortcuts'

/**
 * We found that some of the same shortcuts are used for both
 * the Table and Board views, the objective of this file is to
 * consolidate shortcuts across both views, commonly used with
 * PRC's `ActionMenu` component
 */
export const delKey = () => <KeybindingHint keys="delete" />
export const eKey = () => (!areCharacterKeyShortcutsDisabled() ? <KeybindingHint keys="e" /> : null)
