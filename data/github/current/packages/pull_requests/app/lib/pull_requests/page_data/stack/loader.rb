# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Stack
      class Loader
        class StackedPullRequestData < T::Struct
          const :is_unstackable, T::Boolean
          const :title, String
          const :number, Integer
          const :state, String
          const :url, String
          const :head_oid, String
        end

        class Data < T::Struct
          const :id, Integer
          const :base_branch, String
          const :repository_owner_login, String
          const :repository_name, String
          const :position, Integer
          const :size, Integer
          const :pulls, T::Array[StackedPullRequestData]
        end

        sig { params(pull_request: PullRequest, current_user: T.nilable(User), repository: ::Repository).returns(T.nilable(Data)) }
        def self.load(pull_request:, current_user:, repository:)
          new(pull_request:, current_user:, repository:).load
        end

        sig { params(pull_request: PullRequest, current_user: T.nilable(User), repository: ::Repository).void }
        def initialize(pull_request:, current_user:, repository:)
          @pull_request = pull_request
          @current_user = current_user
          @repository = repository
        end

        sig { returns(T.nilable(Data)) }
        def load
          return unless FeatureFlag.vexi.enabled?(
            :pull_request_stacks,
            [@repository, @current_user].compact,
            default: false,
          )

          stack_entry = @pull_request.stack_entry
          stack = stack_entry&.stack
          return if stack_entry.nil? || stack.nil?

          sorted_entries = stack.entries.reorder(position: :desc)

          GitHub::PrefillAssociations.prefill_associations(
            sorted_entries,
            { pull_request: [:auto_merge_request, :issue, :repository, { base_repository: { merge_queues: :entries } }] },
            available_records: [stack_entry, @pull_request, @repository],
          )

          Data.new(
            id: stack.id,
            base_branch: stack.base_ref,
            repository_owner_login: @repository.owner_display_login,
            repository_name: @repository.name,
            position: stack_entry.position,
            size: sorted_entries.size,
            pulls: load_pulls(sorted_entries:, stack:),
          )
        end

        private

        sig { params(sorted_entries: T::Enumerable[PullRequests::StackEntry], stack: PullRequests::Stack).returns(T::Array[StackedPullRequestData]) }
        def load_pulls(sorted_entries:, stack:)
          sorted_entries.filter_map do |entry|
            pull = entry.pull_request
            next if pull.nil?

            # Prefill stack_entry and stack on each pull request to avoid N+1 queries when is_unstackable? calls
            # in_merge_queue?. The scoped has_one :stack_entry association on PullRequest prevents matching
            # available_records via GitHub::PrefillAssociations#prefill_associations, so we set targets directly
            # using same pattern as GitHub::PrefillAssociations#prefill_association.
            pull.association(:stack_entry).target = entry # rubocop:disable GitHub/DontCallAssociationTargetEquals
            pull.association(:stack).target = stack # rubocop:disable GitHub/DontCallAssociationTargetEquals

            StackedPullRequestData.new(
              is_unstackable: pull.is_unstackable?,
              title: pull.title,
              number: pull.number,
              state: PullRequest::Icon::State.for_pull_request(pull).to_s.upcase,
              url: T.must(pull.permalink(include_host: false)),
              head_oid: pull.head_sha,
            )
          end
        end
      end
    end
  end
end
