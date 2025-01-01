# typed: true
# frozen_string_literal: true

class GitHubModels::Block < ApplicationRecord::Domain::GitHubModels
  include GitHubModels::IBlock

  self.table_name = "models_blocks"
  self.strict_loading_by_default = true

  belongs_to :actor, class_name: "::User", required: true, inverse_of: :created_github_models_blocks
  belongs_to :user, class_name: "::User", required: true, inverse_of: :received_github_models_blocks

  enum :state, {
    active: 0,
    revoked: 1,
  }

  validates :reason, :state, presence: true

  ACTIVE_STATE = "blocked"
  REVOKED_STATE = "unblocked"
  BLOCK_NOTIFICATION_SLACK_CHANNEL = "#github-models-ops"

  # Reasons for blocking a user from using GitHub Models
  ACCOUNT_SHARING = "Do not reinstate: fake accounts IP sharing and evading Models rate limits."
  ACCOUNT_FARMING = "Do not reinstate: account farming, evading Models rate limits."
  EXCESSIVE_429 = "Can reinstate with warning: excessive 429s in the last day."
  GENERAL_ABUSE = "General abuse."
  OTHER = "Other."

  sig { returns T::Array[String] }
  def self.reasons
    [ACCOUNT_SHARING, ACCOUNT_FARMING, EXCESSIVE_429, GENERAL_ABUSE, OTHER]
  end

  sig { params(user: T.nilable(::User)).returns(T::Boolean) }
  def self.blocked?(user)
    return false unless user
    user.received_github_models_blocks.active.any?
  end

  sig { params(actor: ::User, user: ::User, reason: String, skip_output: T::Boolean).returns(T::Boolean) }
  def self.block(actor:, user:, reason:, skip_output: false)
    if blocked?(user)
      unless skip_output
        msg = "#{actor.display_login} attempted to block already blocked user #{user.display_login} for \"#{reason}\""
        GitHub::Chatterbox.client.say!(BLOCK_NOTIFICATION_SLACK_CHANNEL, msg)
      end
      return false
    end

    if user.hammy?
      unless skip_output
        msg = "#{actor.display_login} attempted to block hammy user #{user.display_login} for \"#{reason}\""
        GitHub::Chatterbox.client.say!(BLOCK_NOTIFICATION_SLACK_CHANNEL, msg)
      end
      return false
    end

    user_is_trusted = TrustTiers::Tier.for_billable_owner(user).tier <= TrustTiers::Tier::TRUSTED
    if user_is_trusted
      unless skip_output
        msg = "#{actor.display_login} attempted to block trusted user #{user.display_login} for \"#{reason}\""
        GitHub::Chatterbox.client.say!(BLOCK_NOTIFICATION_SLACK_CHANNEL, msg)
      end
      return false
    end

    GitHub.logger.info(
      "Blocking user for GitHub Models",
      "gh.user.login": user.display_login,
      "gh.actor.login": actor.display_login,
      "reason": reason,
    ) unless skip_output

    block_record = user.received_github_models_blocks.create(actor: actor, state: :active, reason: reason)
    return false unless block_record.persisted?

    unless skip_output
      msg = "#{actor.display_login} blocked #{user.display_login} for \"#{reason}\""
      GitHub::Chatterbox.client.say!(BLOCK_NOTIFICATION_SLACK_CHANNEL, msg)
    end
    true
  end

  sig { params(actor: ::User, user: ::User, reason: T.nilable(String), skip_output: T::Boolean).returns(T::Boolean) }
  def self.unblock(actor:, user:, reason: nil, skip_output: false)
    return true unless blocked?(user) # nothing to do

    GitHub.logger.info(
      "Unblocking user for GitHub Models",
      "gh.user.login": user.display_login,
      "gh.actor.login": actor.display_login,
      "reason": reason,
    ) unless skip_output

    total_rows_updated = user.received_github_models_blocks.active.update_all(state: :revoked)
    total_rows_updated >= 1
  end
end
