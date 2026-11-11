# typed: true
# frozen_string_literal: true

class Hook::Event::UserEvent < Hook::Event
  # this event is only available in GHE Server
  # adding the check for a single business environment here rather than
  # wrapping the entire class in a check to so that the rest of the codebase
  # doesn't need special handling for whether the class is defined or not
  supports_targets Business if GitHub.single_business_environment?

  description "User is created or deleted"

  event_attr :action, :user_id, required: true
  event_attr :actor_id

  def user
    @user ||= User.find_by(id: user_id)
  end

  def deliverable?
    user.present?
  end

  def actor
    @actor ||= (User.find_by(id: actor_id) || User.ghost)
  end
end
