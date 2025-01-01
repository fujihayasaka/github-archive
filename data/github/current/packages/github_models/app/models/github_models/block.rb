# typed: true
# frozen_string_literal: true

class GitHubModels::Block < ApplicationRecord::Domain::Integrations
  self.table_name = "azure_models_blocks"
  self.strict_loading_by_default = true

  # rubocop:todo Rails/InverseOf
  belongs_to :actor, class_name: "::User", foreign_key: :actor_id, strict_loading: false
  belongs_to :user, class_name: "::User", foreign_key: :user_id, strict_loading: false
  # rubocop:enable Rails/InverseOf

  validates :actor, presence: true
  validates :user, presence: true

  enum :state, {
    active: 0,
    revoked: 1,
  }

  ACTIVE_STATE = "blocked"
  REVOKED_STATE = "unblocked"
  BLOCK_NOTIFICATION_SLACK_CHANNEL = "#github-models-ops"

  # Reasons for blocking a user from using GitHub Models
  ACCOUNT_SHARING = "Do not reinstate: fake accounts IP sharing and evading Models rate limits."
  ACCOUNT_FARMING = "Do not reinstate: account farming, evading Models rate limits."
  EXCESSIVE_429 = "Can reinstate with warning: excessive 429s in the last day."
  GENERAL_ABUSE = "General abuse."
  OTHER = "Other."

  def self.reasons
    [ACCOUNT_SHARING, ACCOUNT_FARMING, EXCESSIVE_429, GENERAL_ABUSE, OTHER]
  end

  def self.blocked?(user)
    return false unless user

    active.where(user: user).exists?
  end

  sig { params(actor: ::User, user: ::User, reason: String).returns(T::Boolean) }
  def self.block!(actor:, user:, reason:)
    if blocked?(user)
      msg = "#{actor.display_login} attempted to block already blocked user #{user.display_login} for \"#{reason}\""
      GitHub::Chatterbox.client.say!(BLOCK_NOTIFICATION_SLACK_CHANNEL, msg)
      return false
    end

    if user.hammy?
      msg = "#{actor.display_login} attempted to block hammy user #{user.display_login} for \"#{reason}\""
      GitHub::Chatterbox.client.say!(BLOCK_NOTIFICATION_SLACK_CHANNEL, msg)
      return false
    end

    user_is_trusted = TrustTiers::Tier.for_billable_owner(user).tier <= TrustTiers::Tier::TRUSTED
    if user_is_trusted
      msg = "#{actor.display_login} attempted to block trusted user #{user.display_login} for \"#{reason}\""
      GitHub::Chatterbox.client.say!(BLOCK_NOTIFICATION_SLACK_CHANNEL, msg)
      return false
    end

    GitHub.logger.info(
      "Blocking user for GitHub Models",
      "gh.user.login": user.display_login,
      "gh.actor.login": actor.display_login,
      "reason": reason,
    )

    create!(actor: actor, user: user, state: :active, reason: reason)

    msg = "#{actor.display_login} blocked #{user.display_login} for \"#{reason}\""
    GitHub::Chatterbox.client.say!(BLOCK_NOTIFICATION_SLACK_CHANNEL, msg)
    true
  end

  def self.unblock!(actor:, user:, reason:)
    return unless blocked?(user)

    GitHub.logger.info(
      "Unblocking user for GitHub Models",
      "gh.user.login": user.display_login,
      "gh.actor.login": actor.display_login,
      "reason": reason,
    )

    active.where(user: user).update_all(state: :revoked)
  end
end
