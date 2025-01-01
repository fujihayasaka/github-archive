# typed: true
# frozen_string_literal: true

module Configurable
  module OrgMembershipVisibility
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    DEFAULT_ORG_MEMBERSHIP_PUBLIC_KEY = "default_org_membership_public".freeze

    # Set the default org membership visibility for the installation.
    #
    # visibility - The visibility as a String, either "public" or "private".
    # actor      - The User applying the setting.
    # enforce    - A Boolean indicating whether the visibility is enforced
    #              on org members.
    #
    # The default org membership visibility maps to the
    # default_org_membership_public config entry in the following states:
    #
    # - Private:              default_org_membership_public is *not set*
    # - Private and enforced: default_org_membership_public set to "false" and
    #                         final set to true
    # - Public:               default_org_membership_public set to "true"
    # - Public and enforced:  default_org_membership_public set to "true" and
    #                         final set to true
    def set_default_org_membership_visibility(visibility, actor, enforce)
      case visibility
      when "public"
        config.enable!(DEFAULT_ORG_MEMBERSHIP_PUBLIC_KEY, actor, enforce)
      when "private"
        if enforce
          # Set the key to the default value of "false" if enforced
          config.disable!(DEFAULT_ORG_MEMBERSHIP_PUBLIC_KEY, actor, enforce)
        else
          # Delete the key if not enforcing the default value
          config.delete(DEFAULT_ORG_MEMBERSHIP_PUBLIC_KEY, actor)
        end
      else
        raise ArgumentError, %Q[Expected visibility to be "public" or "private", not #{visibility.inspect}]
      end
    end

    # Return the default org membership visibility.
    #
    # Returns a String, either "public" or "private".
    def default_org_membership_visibility
      default_org_membership_visibility_public? ? "public" : "private"
    end

    # Return true if the default org membership visibility is public,
    # otherwise false.
    #
    # Returns a Boolean.
    def default_org_membership_visibility_public?
      config.enabled?(DEFAULT_ORG_MEMBERSHIP_PUBLIC_KEY)
    end

    # Return true if the default org membership visibility is enforced,
    # otherwise false (regardless of whether default visibility is set to
    # public or private).
    #
    # Returns a Boolean.
    def default_org_membership_visibility_enforced?
      config.final?(DEFAULT_ORG_MEMBERSHIP_PUBLIC_KEY)
    end

    # Return true if the default org membership visibility is public and
    # enforced, otherwise false.
    #
    # Returns a Boolean.
    def public_org_membership_visibility_enforced?
      default_org_membership_visibility_enforced? &&
      default_org_membership_visibility_public?
    end

    # Return true if the default org membership visibility is private and
    # enforced, otherwise false.
    #
    # Returns a Boolean.
    def private_org_membership_visibility_enforced?
      default_org_membership_visibility_enforced? &&
      !default_org_membership_visibility_public?
    end
  end
end
