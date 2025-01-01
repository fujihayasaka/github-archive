# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddDiscussionPollVote < Platform::Mutations::Base
      description "Vote for an option in a discussion poll."
      minimum_accepted_scopes ["public_repo"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :poll_option_id,
        ID,
        description: "The Node ID of the discussion poll option to vote for.",
        required: true,
        loads: Objects::DiscussionPollOption

      field :poll_option,
        Objects::DiscussionPollOption,
        description: "The poll option that a vote was added to.",
        null: true
      error_fields

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, poll_option:, **inputs)
        poll_option.async_poll.then do |poll|
          poll.async_discussion.then do |discussion|
            permission.async_repo_and_org_owner(discussion).then do |repo, org|
              permission.access_allowed?(
                :add_discussion_poll_vote,
                repo: repo,
                current_org: org,
                resource: discussion,
                allow_integrations: false,
                allow_user_via_granular_actor: true,
              )
            end
          end
        end
      end

      def resolve(poll_option:, execution_errors:, **inputs)
        voter = DiscussionPollVote::Creator.new(user: context[:viewer], option: poll_option)

        if voter.create
          # Reload to pick up updated vote count field
          { poll_option: poll_option.reload, errors: [] }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(voter, execution_errors)
          { poll_option: nil, errors: voter.errors }
        end
      end
    end
  end
end
