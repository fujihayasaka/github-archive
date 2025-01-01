# typed: true
# frozen_string_literal: true

# Allow GitHub features to determine if they are *only* shipped
# to GitHub employees, or if they are also enabled for users outside
# of GitHub.
#
# # A Note on this Implementation...
#
# Ideally we wouldn't be injecting stuff into Flipper::Feature but it's the safest
# way to ensure that all feature checks are done in a uniform way for now. Longer term
# we discussed adding the ability to configure the set of gates flipper uses so that custom
# gates can be added, but that would likely be a breaking change and out of scope for
# us at this point. See https://github.com/github/github/pull/103071 for more.
#
# NOTE: We cannot tell if a Feature is enabled for arbitrary
# non-Hubbers via an explict actor add, but that should be a highly
# unusual case.
#
# The EmployeeMode module is prepended to Flipper::Feature itself
module Flipper
  module EmployeeMode
    # Is the feature enabled for GitHub employees *only*? Or do its gates
    # also enable the feature for non-Hubbers?
    #
    # Returns a Boolean
    def enabled_for_employees_only?
      return false if globally_enabled?
      return false if percentage_enabled?
      return false if non_employee_group_enabled?

      # The feature is shipped only to specific individuals (presumably Hubbers
      # on a team), or to :preview_features (i.e., GitHub employees) - so employees only!
      true
    end

    # This method overrides Feature#enabled? via Module.prepend. As the logic is governed by
    # the internal state of the actor rather than the values stored in Flipper, this essentially
    # acts as an override and short circuits the feature check when the actor is in a certain
    # state.
    def enabled?(thing = nil)
      return false if thing.is_a?(User) && enabled_for_employees_only? && thing.disabled_employee_mode?
      super
    end

    private

    # If the feature is globally enabled, then it has been shipped beyond a
    # single team or GitHub employees.
    def globally_enabled?
      T.bind(self, Flipper::Feature)
      boolean_value == true
    end

    # If the feature is enabled for some percentage of actors or calls,
    # then it has been shipped beyond a single team or GitHub employees.
    def percentage_enabled?
      T.bind(self, Flipper::Feature)
      percentage_of_actors_value > 0 || percentage_of_time_value > 0
    end

    # If the feature is shipped to groups other than :preview_features,
    # then it has been shipped beyond a single team or GitHub employees.
    def non_employee_group_enabled?
      T.bind(self, Flipper::Feature)
      groups_value.any? { |group| group.to_s != Groups.preview_features.name.to_s }
    end
  end
end

Flipper::Feature.prepend(Flipper::EmployeeMode)
