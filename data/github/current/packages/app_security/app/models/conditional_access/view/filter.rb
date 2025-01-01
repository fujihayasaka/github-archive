# typed: true
# frozen_string_literal: true

# This is the Web view specific implementation of ConditionalAccess::Filter
#
# Some things to note about this Filter:
# - safe_request_method? is hardcoded to false so that the policies that depend
# on that for applicability don't consider that. The request type (GET, POST, etc.)
# shouldn't be taken into consideration since the methods of this filter are invoked
# intentionally from views on render
#
# the location is a :view, but the callback is likely a controller instance
# since this Filter is used for CAP considerations in web views
#
# We are utilizing the Filter specifically for its caching functionality, as
# opposed to the Enforcer
class ConditionalAccess::View::Filter < ConditionalAccess::Web::Filter
  include ConditionalAccess::Policy::EmuOwnership

  def initialize(callback)
    super(callback, do_authzd_science: true)
  end

  def conditional_access_policies
    [:emu_ownership]
  end

  def authzd_science_policies
    [:emu_ownership]
  end

  def location
    :view
  end

  def safe_request_method?
    false
  end

  def authorized?(resource:, policy:)
    resources_to_authorize = [resource]

    viewable_resources = authorized_resources(resources_to_authorize, only: policy)
    return true if resources_to_authorize == viewable_resources

    false
  end
end
