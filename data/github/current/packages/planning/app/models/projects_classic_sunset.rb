# typed: strict
# frozen_string_literal: true

module ProjectsClassicSunset
  extend T::Helpers

  SUNSET_UI_FLAG = :projects_classic_sunset_ui
  REDIRECT_MIGRATED_PROJECTS_FLAG = :projects_classic_redirect_migrated_projects

  # This is a support/staff-only flag to allow overriding the Projects (classic) sunset in the rare situation we need
  # to still allow it to be accessible.
  SUNSET_OVERRIDE_FLAG = :projects_classic_sunset_override

  # This is a hard-coded list of customers who will still be allowed to use Projects (classic) after the sunset.
  SUNSET_OVERRIDE_ORGANIZATIONS = T.let([
    53582822, # unicorns-r-us
    55292607, # intel-innersource
    71398875, # intel-restricted
  ], T::Array[Integer])

  sig { params(entity: T.nilable(User), org: T.nilable(Organization)).returns(T::Boolean) }
  def self.projects_classic_ui_enabled?(entity, org: nil)
    # If the entity is a user, check if they are a member of a customer org that has the override flag enabled
    # Otherwise, follow the normal logic.
    if org.present? && entity.is_a?(User)
      return true if SUNSET_OVERRIDE_ORGANIZATIONS.include?(org.id) && org.member?(entity)
    end

    # First, check if flags are enabled globally and return accordingly
    return true if GitHub.flipper.enabled?(SUNSET_OVERRIDE_FLAG)
    return false if GitHub.flipper.enabled?(SUNSET_UI_FLAG)
    # Then, default to true if no entity was passed in (e.g. for anonymous users)
    return true if entity.nil?
    # Finally, check if flags are enabled for the entity and return accordingly, defaulting to true if no flags are set
    return true if entity.feature_enabled?(SUNSET_OVERRIDE_FLAG)
    return false if entity.feature_enabled?(SUNSET_UI_FLAG)

    true
  end
end
