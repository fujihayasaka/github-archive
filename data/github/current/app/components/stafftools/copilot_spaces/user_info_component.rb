# typed: true
# frozen_string_literal: true

class Stafftools::CopilotSpaces::UserInfoComponent < ApplicationComponent
  sig { params(user: T.any(User, Organization)).void }
  def initialize(user:)
    @user = user
  end

  private

  sig { returns T.any(User, Organization) }
  attr_reader :user

  sig { returns T.nilable(T::Boolean) }
  def render?
    return false unless GitHub.copilot_enabled? && logged_in?
    true
  end

  sig { returns T.nilable(Organization) }
  memoize def organization
    if user.organization?
      T.cast(user, Organization)
    end
  end

  sig { returns T::Boolean }
  def has_copilot_access?
    return false unless user.user?
    with_database_error_fallback(fallback: false) do
      copilot_user = Copilot::Public::User.new(T.cast(user, User))
      copilot_user.has_copilot_access?
    end
  end

  sig { returns T::Boolean }
  memoize def has_copilot_spaces_access?
    with_database_error_fallback(fallback: false) do
      CopilotSpaces::Enabled.copilot_spaces_enabled_for_user?(user)
    end
  end

  sig { returns Integer }
  def total_copilot_spaces
    # If we have a cached successful result, return it
    return @_spaces_count if defined?(@_spaces_count) && !@_spaces_count.nil?

    # Always retry if we had an error before or no cached result
    begin
      count = CopilotSpace.where(owner: user).count
      @_spaces_count = count  # Cache successful result
      @_spaces_count_error = nil  # Clear any previous error
      count
    rescue => e
      Rails.logger.error "Failed to load CopilotSpace count for #{user.class.name}:#{user.id} (#{user.display_login}): #{e.message}"
      @_spaces_count_error = e
      @_spaces_count = nil  # Don't cache error results
      0
    end
  end

  sig { returns T::Boolean }
  def spaces_count_error?
    defined?(@_spaces_count_error) && @_spaces_count_error.present?
  end

  sig { returns Integer }
  memoize def total_public_spaces
    with_database_error_fallback(fallback: 0) do
      # For personal spaces: base_role != "none" means public
      # For org spaces: base_role != "none" means shared with org members
      CopilotSpace.where(owner: user).where.not(base_role: "none").count
    end
  end

  sig { returns Integer }
  memoize def total_private_spaces
    with_database_error_fallback(fallback: 0) do
      private_space_counts[:private] || 0
    end
  end

  sig { returns Integer }
  memoize def total_shared_private_spaces
    with_database_error_fallback(fallback: 0) do
      private_space_counts[:shared_private] || 0
    end
  end

  # Calculate both private and shared private space counts
  # Returns { private: count, shared_private: count }
  sig { returns T::Hash[Symbol, Integer] }
  memoize def private_space_counts
    # Get all private spaces (base_role = "none") with their creators
    private_spaces = CopilotSpace.where(owner: user, base_role: "none")
                                 .pluck(:id, :creator_id)

    return { private: 0, shared_private: 0 } if private_spaces.empty?

    space_ids = private_spaces.map(&:first)
    space_creator_map = private_spaces.to_h

    # Group by target_id to get all collaborators per space
    collaborators_by_space = UserRole.where(target_type: "CustomCopilot", target_id: space_ids)
                                     .pluck(:target_id, :actor_id)
                                     .group_by(&:first)

    private_count = 0
    shared_count = 0

    space_ids.each do |space_id|
      creator_id = space_creator_map[space_id]
      collaborator_ids = collaborators_by_space[space_id]&.map(&:last) || []

      # Exclude owner and creator from collaborator count
      excluded_ids = [user.id, creator_id].compact
      external_collaborator_ids = collaborator_ids - excluded_ids

      if external_collaborator_ids.any?
        shared_count += 1
      else
        private_count += 1
      end
    end

    { private: private_count, shared_private: shared_count }
  end
end
