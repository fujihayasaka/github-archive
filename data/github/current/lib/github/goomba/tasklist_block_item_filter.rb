# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Goomba node filter that replaces list items in tracking block elements with a custom gh: element
  # so that tracking blost list item elements can be picked up in Async::TaskListItemFilterV2.
  #
  # Issue references are scanned and loaded by Async::IssueMentionFilter.  Deferring list item rendering
  # until the async filters run makes it easy to determine the difference between draft vs non-draft
  # task list items that include issue references.
  class TasklistBlockItemFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper

    LIST_ELEMENTS = %w[ul ol].freeze
    # select list elements that are children of a tracking-block element
    TASKLIST_ITEM_MATCHERS = LIST_ELEMENTS.map { |l| "tracking-block > div.TrackingBlock > #{l} > li" }.join(", ").freeze
    SELECTOR = Goomba::Selector.new(match: TASKLIST_ITEM_MATCHERS)

    def selector
      SELECTOR
    end

    def self.feature_flags
      [:tasklist_block, :tasklist_block_precache]
    end

    def self.enabled?(context)
      return false unless context[:entity].is_a?(Repository)
      # As we do not support cross-references yet, we do not need to unfurl the
      # tracking block if the subject is not a persisted issue. Issue
      # comment previews will have a subject_type populated, but not subject.
      return false unless context[:subject].is_a?(Issue) || context[:subject_type] == "Issue"
      return false unless GitHub.flipper[:tasklist_block].enabled?(context[:entity].owner)
      GitHub.flipper[:tasklist_block_precache].enabled?(context[:entity].owner)
    end

    def call(node)
      # set a gh: namespaced attribute to the nodes original markdown
      # - the gh: namespaced attribute will cause the node to be transformed
      #   by Async::TaskListItemFilterV2 via GithubReferenceFilter
      # - the nodes original markdown is used to create draft issue tasklist items
      original_md = scratch.fetch(:original_tasklist_items, []).shift
      node["gh:tracking-block-item"] = "#{original_md}"
      nil
    end
  end
end
