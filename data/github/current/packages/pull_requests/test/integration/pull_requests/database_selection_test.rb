# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests

  CLUSTERS = [
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Repositories,
  ]

  class TestController < ApplicationController
    include PullRequests::DatabaseSelection

    before_action :find_repo

    skip_before_action :perform_conditional_access_checks

    around_action :use_replica_clusters_around_action, only: [:replicas_around_action_test]

    prepend_around_action :use_replica_clusters_prepend_around_action, only: [:replicas_prepend_around_action_test]

    around_action :use_replica_clusters_with_primary_override, only: [:replicas_around_action_with_primary_override_test]

    def baseline_test
      make_queries
      head :ok
    end

    def replicas_around_action_test
      make_queries
      head :ok
    end

    def replicas_prepend_around_action_test
      make_queries
      head :ok
    end

    def replicas_around_action_with_primary_override_test
      ActiveRecord::Base.connected_to_many([ApplicationRecord::IssuesPullRequests], role: :writing) do
        _issue = @repo.issues.first
      end
      _project = @repo.memex_projects.first

      head :ok
    end

    private

    def use_replica_clusters_around_action(&block)
      use_replica_clusters(CLUSTERS, &block)
    end

    def use_replica_clusters_prepend_around_action(&block)
      use_replica_clusters(CLUSTERS, &block)
    end

    def use_replica_clusters_with_primary_override(&block)
      use_replica_clusters(CLUSTERS, &block)
    end

    def find_repo
      @repo = Repositories::Public.find_active!(params[:id].to_i)
    end

    # simulate reads against clusters
    def make_queries
      _issue = @repo.issues.first
      _project = @repo.memex_projects.first
    end
  end

  class DatabaseSelectionTest < GitHub::IntegrationTestCase
    # Necessary when running `./bin/rails test` directly against this file
    ::TestRoutes = ActionDispatch::Routing::RouteSet.new unless defined?(::TestRoutes)

    setup_once do
      TestRoutes.draw do
        post "/test/baseline/:id", to: "pull_requests/test#baseline_test"
        post "/test/replicas-around-action/:id", to: "pull_requests/test#replicas_around_action_test"
        post "/test/replicas-prepend-around-action/:id", to: "pull_requests/test#replicas_prepend_around_action_test"
        post "/test/replicas-around-action-with-primary-override/:id", to: "pull_requests/test#replicas_around_action_with_primary_override_test"
      end
    end

    teardown_once do
      TestRoutes.clear!
    end

    fixtures do
      @repository = create(:repository)
    end

    context "database cluster selection" do
      test "baseline", skip_enterprise: true do
        queries = log_query_connection_types(clusters: CLUSTERS) do
          post "/test/baseline/#{@repository.id}"
        end
        assert response.ok?, "Expected a successful response, got #{response.status}"

        # Baseline: default behaviour without any per-action DB selection applied.
        # Because this is a POST request, everything goes to primaries.
        assert_empty queries[:replica]
        assert_same_elements(
          CLUSTERS,
          queries[:primary]
        )
      end

      test "around_action", skip_enterprise: true do
        queries = log_query_connection_types(clusters: CLUSTERS) do
          post "/test/replicas-around-action/#{@repository.id}"
        end
        assert response.ok?, "Expected a successful response, got #{response.status}"

        # with around_action, the before_action :find_repo reads from the Repositories primary
        assert_equal queries[:primary], [ApplicationRecord::Repositories]
        assert_equal queries[:replica], [ApplicationRecord::IssuesPullRequests, ApplicationRecord::Memex]
      end

      test "prepend_around_action", skip_enterprise: true do
        queries = log_query_connection_types(clusters: CLUSTERS) do
          post "/test/replicas-prepend-around-action/#{@repository.id}"
        end
        assert response.ok?, "Expected a successful response, got #{response.status}"

        # with prepend_around_action, the before_action :find_repo reads from the Repositories replica
        assert_empty queries[:primary]
        assert_same_elements(
          CLUSTERS,
          queries[:replica]
        )
      end

      test "primary override", skip_enterprise: true do
        queries = log_query_connection_types(clusters: CLUSTERS) do
          post "/test/replicas-around-action-with-primary-override/#{@repository.id}"
        end
        assert response.ok?, "Expected a successful response, got #{response.status}"

        assert_equal queries[:primary], [ApplicationRecord::Repositories, ApplicationRecord::IssuesPullRequests]
        assert_equal queries[:replica], [ApplicationRecord::Memex]
      end
    end

    private

    def log_query_connection_types(clusters:, &block)
      _, queries = log_queries(&block)

      result = { primary: [], replica: [] }
      queries.each do |query|
        next unless clusters.include?(query.connection_class)
        if query.on_primary
          result[:primary] << query.connection_class
        else
          result[:replica] << query.connection_class
        end
      end
      result
    end
  end
end
