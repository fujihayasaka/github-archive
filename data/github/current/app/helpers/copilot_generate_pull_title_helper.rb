# typed: true
# frozen_string_literal: true

module CopilotGeneratePullTitleHelper
  extend T::Helpers
  include GitHub::Memoizer

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
  def current_copilot_user_v2; end

  sig { returns(T::Boolean) }
  def copilot_generate_pull_title_allowed?
    copilot_user = current_copilot_user_v2
    return false unless copilot_user

    copilot_user.show_copilot_functionality? && copilot_user.dotcom_chat_enabled?
  end

  sig { returns(T::Boolean) }
  memoize def copilot_generate_pull_title_enabled_for_user?
    FeatureFlag.vexi.enabled?("copilot_generate_pull_title", current_user, default: false)
  end

  sig { params(comparison: T.untyped).returns(T::Array[T::Hash[Symbol, String]]) }
  def copilot_generate_pull_title_commits_data(comparison)
    return [] if comparison.nil?

    comparison.paginated_commits(page: 1).map do |commit|
      {
        oid: commit.oid,
        message: commit.message
      }
    end
  end
end
