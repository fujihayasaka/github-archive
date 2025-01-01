# typed: true
# frozen_string_literal: true

class Hook::Event::WatchEvent < Hook::Event
  class UnknownStarredType < StandardError
    def initialize(starred_type)
      super "Unknown star.starred_type: #{starred_type}"
    end
  end

  supports_targets *DEFAULT_TARGETS
  description "User stars a repository."

  event_attr :user_id, :starred_id, :starred_type, required: true

  def action
    :started
  end

  def user
    @user ||= User.find(user_id)
  end

  def starred
    @starred ||= if repository_starred?
      Repositories::Public.find_active(starred_id)
    else
      raise UnknownStarredType.new(starred_type)
    end
  end

  def target_repository
    starred
  end

  def actor
    user
  end

  def deliverable?
    target_repository.present?
  end

  private

  def repository_starred?
    starred_type == "Repository"
  end
end
