# typed: true
# frozen_string_literal: true

class GhostGitHubApp < Integration
  include Singleton

  def name
    "Deleted GitHub App"
  end

  def primary_avatar_url
    User.ghost.primary_avatar_url
  end

  def preferred_avatar_url(size: 80)
    User.ghost.primary_avatar_url(size)
  end

  def readonly?
    true
  end

  def owner
    User.ghost
  end
end
