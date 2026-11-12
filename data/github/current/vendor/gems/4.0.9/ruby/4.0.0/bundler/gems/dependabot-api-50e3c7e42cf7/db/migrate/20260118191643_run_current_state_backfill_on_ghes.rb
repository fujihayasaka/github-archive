# frozen_string_literal: true

require "dependabot/transitions/20251230042641_backfill_current_state_values"

class RunCurrentStateBackfillOnGhes < ActiveRecord::Migration[7.2]
  def up
    return unless Dependabot.enterprise?

    transition = Dependabot::Transitions::BackfillCurrentStateValues.new(dry_run: false)
    transition.perform
  end

  def down
    # no-op, to fully reverse this migration the current_state columns need to be dropped
    # which is handled in the AddCurrentStates migration's down method
  end
end
