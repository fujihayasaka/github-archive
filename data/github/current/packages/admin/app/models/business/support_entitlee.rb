# typed: true
# frozen_string_literal: true

# Represents a User entitled to the HelpHub support portal for a Business
class Business::SupportEntitlee
  include Ability::Actor

  def initialize(user)
    @user = user
  end

  def ability_type
    "SupportEntitlee"
  end

  def ability_id
    @user.id
  end

  # Can the user be a given permission over a given target?
  def can_be_granted_permission_over!(subject, action)
    @user.can_be_granted_permission_over!(subject, action)
  end
end
