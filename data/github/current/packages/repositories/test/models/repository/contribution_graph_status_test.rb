# typed: true
# frozen_string_literal: true

require "test_helper"

module RepositoryContributionGraphStatusSharedTests
  extend T::Helpers

  requires_ancestor do
    GitHub::TestCase
  end

  def assert_fresh_data_overrides_stale(graph_name, stale_data, fresh_data, parsed_stale: [], now: Time.utc(2011, 2, 15))
    with_cache_enabled do
      Timecop.freeze(now) do
        @contributor_status.update!(
          last_indexed_oid: @contributor_status.repository.default_oid,
          last_viewed_at: 5.hours.ago,
          last_indexed_at: 10.minutes.ago,
        )
        @contributor_status.stubs(:data_fully_indexed?).returns(false)
        @contributor_status.stubs(:serve_stale_data?).returns(true)

        GitHub::RepoGraph::Eventer.any_instance.stubs("fetch_#{graph_name}_data".to_sym => stale_data)
        assert_equal parsed_stale, @contributor_status.send("#{graph_name}_data")

        # ensure the stale data remains cached even though the eventer data has changed
        GitHub::RepoGraph::Eventer.any_instance.stubs("fetch_#{graph_name}_data".to_sym => fresh_data)
        assert_equal parsed_stale, @contributor_status.send("#{graph_name}_data")

        # now that up to date has changed, we should be getting the new data
        @contributor_status.stubs(:data_fully_indexed?).returns(true)
        @contributor_status.stubs(:serve_stale_data?).returns(false)

        yield @contributor_status.send("#{graph_name}_data")
      end
    end
  end
end
