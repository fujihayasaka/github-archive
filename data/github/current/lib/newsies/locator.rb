# typed: true
# frozen_string_literal: true

module Newsies
  # This module allow us to use models that don't implement GlobalID::Identification
  # The idea is to use custom locators instead of reopening them
  module Locator

    class ObjectNotLocable; end
    class NotFound < StandardError; end

    # CommitLocator creates a global_id for Commit object and loads these objects
    # using that global_id.
    # Commit objects are not regular ActiveRecord models, but instead of reopening
    # them adding GlobalID functionality we use this wrapper inside Newsies.
    class CommitLocator
      include GlobalID::Identification

      # Return a Commit instance from it's #global_id (repository_id + oid)
      sig { params(id: String).returns(Commit) }
      def self.find(id)
        repository_id, oid = id.split(":")
        repository = if FeatureFlag.vexi.enabled?(:repos_by_id_lib, default: false)
          T.cast(Repositories.domain.by_id(repository_id.to_i), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
        else
          Repository.find_by(id: repository_id)
        end

        raise NotFound, "Repository with ID #{repository_id} not found" unless repository

        commit = begin
          repository.commits.find(oid)
        rescue GitRPC::ObjectMissing
          nil
        end

        raise NotFound, "Commit with OID #{oid} not found" unless commit

        commit
      end

      sig { params(commit: Commit).void }
      def initialize(commit)
        @commit = commit
      end

      sig { returns(String) }
      def id
        # NOTE: This is an internal global id composed with the repisotiry and commit's oid
        @commit.global_id
      end
    end

    # Return a thread instance (Issue, Commit, etc) associated to a NotificationSummary
    # The main idea behind this class is that callers that only have a NotificationSummary
    # information can delegate finding the thread to background jobs without incurring in
    # extra queries.
    #
    # Example:
    #
    #   summary = NotificationSummary.fetch_and_update!(repo, issue, issue)
    #   gid = Newsies::Locator::ThreadBySummaryLocator.new(summary).to_global_id
    #   issue == GlobalID::Locator.locate(gid)
    class ThreadBySummaryLocator
      include GlobalID::Identification

      sig { params(id: T.any(Integer, String)).returns(T.untyped) }
      def self.find(id)
        NotificationSummary.find(id).thread
      end

      sig { params(summary: NotificationSummary).void }
      def initialize(summary)
        @summary = summary
      end

      sig { returns(Integer) }
      def id
        @summary.id
      end
    end

    sig { params(object: T.untyped).returns(T.nilable(GlobalID)) }
    def self.to_global_id(object)
      case object
      when ::Commit
        CommitLocator.new(object).to_global_id
      else
        nil
      end
    end
  end
end
