# typed: true
# frozen_string_literal: true

require "github/transitions/20230228203236_add_edit_category_on_discussion_fgp"

class AddEditCategoryOnDiscussionFgpTransition < ActiveRecord::Migration[7.1]
  def up
    return if !GitHub.enterprise? && !GitHub::AppEnvironment.development?
    transition = GitHub::Transitions::AddEditCategoryOnDiscussionFgp.new(dry_run: false)
    transition.perform
  end
end
