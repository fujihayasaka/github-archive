# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Stack
      module Overview
        class Loader
          class StackEntryData < T::Struct
            const :is_unstackable, T::Boolean
            const :number, Integer
            const :title, String
            const :state, String
            const :url, String
            const :head_branch, String
          end

          class StackData < T::Struct
            const :id, Integer
            const :base_branch, String
            const :repository_owner_login, String
            const :repository_name, String
            const :number, Integer
            const :position, Integer
            const :size, Integer
            const :all_pulls_locked, T.nilable(T::Boolean)
            const :pulls, T::Array[StackEntryData]
          end

          sig { params(pull_request: PullRequest).returns(T.nilable(StackData)) }
          def self.load(pull_request:)
            new(pull_request:).load
          end

          sig { params(pull_request: PullRequest).void }
          def initialize(pull_request:)
            @pull_request = pull_request
          end

          sig { returns(T.nilable(StackData)) }
          def load
            repository = @pull_request.repository
            return nil if repository.nil?
            return nil unless PullRequests::Stacks.enabled?([repository])
            GitHub::PrefillAssociations.prefill_associations([@pull_request], :stack)

            stack_entry = @pull_request.stack_entry
            stack = @pull_request.stack
            return nil if stack_entry.nil? || stack.nil?
            locked_pr_filtering_enabled = FeatureFlag.vexi.enabled?(:pull_request_stacks_prevent_unstacking_locked_prs, repository, default: false)

            if locked_pr_filtering_enabled
              GitHub::PrefillAssociations.prefill_associations(
                [stack],
                { entries: { pull_request: [:auto_merge_request, :issue, :repository, { base_repository: { merge_queues: :entries } }] } }
              )

              sorted_entries = stack.entries.sort_by(&:position).reverse
              pull_records = sorted_entries.filter_map(&:pull_request)

              GitHub::PrefillAssociations.prefill_batch_method(pull_records, :merge_queue)
              merge_queues = pull_records.filter_map(&:merge_queue).uniq
              GitHub::PrefillAssociations.prefill_associations(merge_queues, [:entries])

              pulls = pull_records.map do |pull|
                StackEntryData.new(
                  is_unstackable: pull.is_unstackable?,
                  number: pull.number,
                  title: pull.title,
                  state: PullRequest::Icon::State.for_pull_request(pull).to_s.upcase,
                  url: T.must(pull.permalink(include_host: false)),
                  head_branch: pull.display_head_ref_name,
                )
              end
              all_pulls_locked = pulls.none?(&:is_unstackable)
            else
              GitHub::PrefillAssociations.prefill_associations([stack], { entries: { pull_request: [:issue, :repository] } })

              sorted_entries = stack.entries.sort_by(&:position).reverse
              pulls = sorted_entries.filter_map do |entry|
                pull = entry.pull_request
                next if pull.nil?

                StackEntryData.new(
                  is_unstackable: false,
                  number: pull.number,
                  title: pull.title,
                  state: PullRequest::Icon::State.for_pull_request(pull).to_s.upcase,
                  url: T.must(pull.permalink(include_host: false)),
                  head_branch: pull.display_head_ref_name,
                )
              end
              all_pulls_locked = nil
            end

            StackData.new(
              id: stack.id,
              base_branch: stack.base_ref,
              repository_owner_login: repository.owner_display_login || "",
              repository_name: repository.name || "",
              number: stack.number,
              position: stack_entry.position,
              size: sorted_entries.size,
              all_pulls_locked: all_pulls_locked,
              pulls: pulls,
            )
          end
        end
      end
    end
  end
end
