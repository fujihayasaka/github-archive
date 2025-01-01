# typed: true
# frozen_string_literal: true

module CopilotSpace::StarsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  MAX_DISPLAYED_STARS = 8

  requires_ancestor { CopilotSpace }

  included do
    T.bind(self, T.class_of(CopilotSpace))
    has_many :stars, foreign_key: "custom_copilot_id", class_name: "StarredCopilotSpace", inverse_of: :copilot_space
  end

  sig { params(user: User).returns(T::Boolean) }
  def starred_by?(user)
    # This method relies on the stars assocation having been
    # preloaded to avoid N+1s
    stars.any? { |s| s.user == user }
  end

  def starred_users_react_payload
    stars.order(updated_at: :desc).limit(MAX_DISPLAYED_STARS).includes(:user).map(&:user).compact.map do |user|
      {
        "login" => user.display_login,
        "avatarUrl" => user.primary_avatar_url
      }
    end
  end

  def starred_users_count
    stars.count
  end
end
