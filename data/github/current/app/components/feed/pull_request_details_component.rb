# typed: true
# frozen_string_literal: true

module Feed
  class PullRequestDetailsComponent < ApplicationComponent
    include DiffHelper

    attr_reader :pull_request, :item

    def initialize(pull_request:, item: nil)
      @pull_request = pull_request
      @item = item
    end

    private

    memoize def state
      pull_request.state
    end

    memoize def is_draft?
      pull_request.draft?
    end

    memoize def merged_by
      pull_request.merged_by
    end

    memoize def total_commits
      pull_request.prelude_changed_commits.size
    end

    def click_hydro_attrs(click_target:)
      helpers.feed_clicks_hydro_attrs(
        click_target: click_target,
        feed_item: item,
        metadata: {
          clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::USER,
          clicked_resource_id: merged_by.id,
        }
      )
    end

    def unique_html_id
      item&.unique_html_id
    end
  end
end
