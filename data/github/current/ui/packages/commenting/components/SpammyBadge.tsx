import {LABELS} from '../constants/labels'
import {TEST_IDS} from '../constants/test-ids'
import {CommentHeaderBadge} from './CommentHeaderBadge'

export const SpammyBadge = () => {
  return (
    <CommentHeaderBadge
      variant="danger"
      ariaLabel={LABELS.spammyBadgeTooltip}
      label={LABELS.spammyBadge}
      testId={TEST_IDS.spammyLabel}
    />
  )
}
