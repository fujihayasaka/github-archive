# typed: strict
# frozen_string_literal: true

module Stafftools
  module Repositories
    class MergeCommitRequestsComponent < ApplicationComponent
      extend T::Sig
      include GitHub::Memoizer

      sig { returns(::Repository) }
      attr_reader :repository

      sig { params(repository: ::Repository, page: Integer, per_page: Integer).void }
      def initialize(repository:, page: 1, per_page: 15)
        @repository = repository
        @page = page
        @per_page = per_page
      end

      sig { returns(Integer) }
      def request_count
        scope.count
      end

      sig { returns(T.nilable(Time)) }
      def oldest_request_time
        scope.minimum(:created_at)
      end

      sig { returns(String) }
      def splunk_dashboard_url
        "https://splunk.githubapp.com/en-US/app/gh_reference_app/new_cprmc_architecture?form.repo=#{repository.id}&form.timefilter.earliest=-4h%40m&form.timefilter.latest=now"
      end

      sig { returns(String) }
      def datadog_dashboard_url
        "https://app.datadoghq.com/dashboard/tuj-jhq-4y8/merge-commit-request--mcrb-architecture"
      end

      sig { returns(T::Enumerable[MergeCommitRequest]) }
      memoize def merge_commit_requests
        scope
        .order(created_at: :desc)
        .includes(:pull_request)
        .paginate(page: @page, per_page: @per_page)
      end

      # todo: should probably split off each MCR row into a separate component
      sig { params(mcr: MergeCommitRequest).returns(String) }
      def status_for(mcr)
        if mcr.processing?
          status_text = "Processing"
          scheme = :attention
        else
          status_text = "Waiting"
          scheme = :secondary
        end
        render Primer::Beta::Label.new(float: :right, scheme: scheme).with_content(status_text)
      end

      private

      sig { returns(ActiveRecord::Relation) }
      def scope
        MergeCommitRequest.where(repository: repository)
      end

      sig { returns(T::Boolean) }
      memoize def merge_commit_request_generation_paused?
        MergeCommitRequest.paused_for?(repository)
      end
    end
  end
end
