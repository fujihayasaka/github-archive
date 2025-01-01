# typed: true
# frozen_string_literal: true

require "github/transitions/20230308001159_add_delete_edit_discussion_comment_fgp"

class AddDeleteDiscussionCommentFgpTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !GitHub::AppEnvironment.development?
    transition = GitHub::Transitions::AddDeleteEditDiscussionCommentFgp.new(dry_run: false)
    transition.perform
  end
end
