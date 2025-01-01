# typed: strict
# frozen_string_literal: true

module GitHubModels
  class Domain
    class Blocks < GH::Domain::Base
      include GitHub::Memoizer

      # Public: List of human-readable explanations for why a user might be blocked from Models access.
      sig { returns T::Array[String] }
      def reasons
        Block.reasons
      end

      # Public: Returns the Slack channel used internally for notifications about blocking users from Models.
      sig { returns String }
      def notification_slack_channel
        Block::BLOCK_NOTIFICATION_SLACK_CHANNEL
      end

      # Public: Block a user from GitHub Models.
      sig { params(actor: ::User, user: ::User, reason: String).returns(T::Boolean) }
      def create(actor:, user:, reason:)
        Block.block(actor: actor, user: user, reason: reason)
      end

      # Public: Check if a user is blocked from GitHub Models.
      sig { params(user: T.nilable(::User)).returns(T::Boolean) }
      def exists?(user)
        Block.blocked?(user)
      end

      # Public: Unblock a user from GitHub Models.
      sig { params(actor: ::User, user: ::User, reason: T.nilable(String)).returns(T::Boolean) }
      def destroy(actor:, user:, reason: nil)
        Block.unblock(actor: actor, user: user, reason: reason)
      end

      # Public: Get records of past and current Models blocks for a user.
      sig { params(user: ::User).returns(T::Array[IBlock]) }
      def history_for(user:)
        results = Block.where(user: user).order(created_at: :desc).to_a
        GitHub::PrefillAssociations.prefill_associations(results, :actor)
        results
      end
    end
  end
end
