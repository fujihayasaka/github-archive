# typed: true
# frozen_string_literal: true

module CopilotSpace::StarsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { CopilotSpace }

  included do
    T.bind(self, T.class_of(CopilotSpace))
    has_many :stars, foreign_key: "custom_copilot_id", class_name: "StarredCopilotSpace", inverse_of: :copilot_space
  end

  sig { returns(T::Array[User]) }
  def starred_users
    stars.order(updated_at: :desc).map(&:user).compact
  end

  sig { params(user: User).returns(T::Boolean) }
  def starred_by?(user)
    # This method relies on the stars assocation having been
    # preloaded to avoid N+1s
    stars.any? { |s| s.user == user }
  end

  def starred_users_react_payload
    starred_users.map do |user|
      {
        "login" => user.display_login,
        "avatarUrl" => user.primary_avatar_url
      }
    end
  end
end
