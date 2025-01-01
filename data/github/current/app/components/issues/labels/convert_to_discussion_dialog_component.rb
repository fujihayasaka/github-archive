# typed: true
# frozen_string_literal: true

class Issues::Labels::ConvertToDiscussionDialogComponent < ApplicationComponent
  attr_reader :dialog_id, :repo, :label, :show_button, :issues_count, :button_classes

  def initialize(dialog_id: "", repo:, label:, show_button: true, button_classes: "", issues_count: 1)
    @dialog_id = dialog_id
    @repo = repo
    @label = label
    @label = label
    @show_button = show_button
    @button_classes = button_classes
    @issues_count = issues_count
  end

  def owner
    repo.owner
  end

  def title
    issues_count == 1 ? "Convert issue to discussion" : "Convert issues to discussions"
  end

  def discussion_categories
    @repo.available_discussion_categories
  end
end
