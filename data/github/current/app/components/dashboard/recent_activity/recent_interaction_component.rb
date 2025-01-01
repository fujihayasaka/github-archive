# typed: true
# frozen_string_literal: true

module Dashboard
  module RecentActivity
    class RecentInteractionComponent < ApplicationComponent
      sig { params(interaction: String, interactable: T.any(Issue, PullRequest)).void }
      def initialize(interaction:, interactable:)
        @interaction = interaction
        @interactable = interactable
      end

      private

      sig { returns(String) }
      attr_reader :interaction

      sig { returns(T.any(Issue, PullRequest)) }
      attr_reader :interactable

      sig { returns(T::Hash[Symbol, T.untyped]) }
      memoize def attributes
        helpers.sidebar_recent_interaction_attributes(
          type: interactable.pull_request? ? "pull request" : "issue",
          id: interactable.global_relay_id,
          reason: interaction
        )
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def interactable_attributes
        attributes.merge(hovercard_data_attributes_for_issue_or_pr(interactable))
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def repo_attributes
        attributes.merge(hovercard_data_attributes_for_repository(interactable.repository))
      end

      sig { returns(String) }
      def path_to_resource
        interactable.pull_request? ? pull_request_path(interactable) : issue_path(interactable)
      end

      sig { returns(String) }
      def path_to_repo
        repository_path(interactable.repository)
      end

      sig { returns(PullRequest::Icon) }
      memoize def pull_request_icon
        PullRequest::Icon.new(
          T.cast(interactable, PullRequest),
          permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues https://github.com/github/github/pull/244257
        )
      end
    end
  end
end
