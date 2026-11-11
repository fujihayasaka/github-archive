# typed: true
# frozen_string_literal: true

require "github/transitions/20260105201710_fix_zero_dates_in_user_content_edits"

# This transition runs before `20260105201711_widen_user_content_edit_columns`
# so that invalid `'0000-00-00 00:00:00'` values in `user_content_edits` are
# fixed before the widen migration's `change_table bulk: true` row rewrite,
# which MySQL strict mode would otherwise reject (error 1292). Only relevant for
# GHES upgrades; on dotcom this is a no-op.
#
# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class FixZeroDatesInUserContentEditsTransition < ActiveRecord::Migration[8.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::FixZeroDatesInUserContentEdits.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
