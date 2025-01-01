# typed: true
# frozen_string_literal: true

# Including class must implement #invite_rate_limited_organization
module Orgs::Invitations::RateLimiting
  extend ActiveSupport::Concern
  include GitHub::RateLimitable

  extend T::Helpers
  requires_ancestor { Object }
  # These are type aliases used in conjunction with `T.bind` to assert that
  # particular methods need to be used within a specific context.
  #
  # Since the methods in this module are included in many different places,
  # using `requires_ancestor` is too strict, because it would require that every place
  # this helper is included must inherit from the same set of modules/classes. That would
  # be difficult, since this helper is used across components, controllers, and other helpers.
  #
  # Instead, we use `T.bind` in each method to assert that the method is being used in the
  # correct context. These checks are made statically, as well as at run-time. In this way,
  # as long as the method is called in the correct context, then no errors will occur, and
  # the type-checker will be able to infer the correct type.
  #
  # Heavily inspired by the approach used in MemexesHelper
  UsedInApplicationControllers = T.type_alias do
    T.any(OrganizationsController,
          ProfilesController,
          BillingManagersController,
          Orgs::Controller,
          Profiles::Organization::MembersComponent
        )
  end

  module ClassMethods
    extend T::Helpers
    requires_ancestor { T.class_of(Object) }

    def setup_org_invite_rate_limiting(only:, filter: nil)
      include GitHub::RateLimitedRequest
      T.bind(self, T.class_of(ApplicationController))

      rate_limit_requests \
        only: only,
        if: filter || :org_invite_rate_limit_filter,
        key: :org_invite_rate_limit_key,
        max: :org_invite_rate_limit_max,
        ttl: :org_invite_rate_limit_ttl,
        at_limit: :org_invite_rate_limited,
        render_allow_body: true
    end
  end

  def org_invite_rate_limit_policy
    T.bind(self, UsedInApplicationControllers)
    @org_invite_rate_limit_policy ||= OrganizationInvitation::RateLimitPolicy.new(invite_rate_limited_organization)
  end

  # Whether to rate limit invitations for this organization.
  def org_invite_rate_limit_filter
    T.bind(self, UsedInApplicationControllers)
    return false if invite_rate_limited_organization.nil?
    # Don't rate limit org invites if they aren't enabled
    return false if GitHub.bypass_org_invites_enabled?

    true
  end

  def org_invite_rate_limit_key
    T.bind(self, UsedInApplicationControllers)
    "orgs/invitations.new:org-#{invite_rate_limited_organization.id}"
  end

  def org_invite_rate_limit_max
    org_invite_rate_limit_policy.limit
  end

  def org_invite_rate_limit_ttl
    org_invite_rate_limit_policy.ttl
  end

  def org_invite_rate_limited?
    return true  if Rails.env.development? && T.unsafe(self).params[:fakestate] == "ratelimited"
    return false unless org_invite_rate_limit_filter

    options = {
      max_tries: org_invite_rate_limit_max,
      ttl: org_invite_rate_limit_ttl,
    }
    rate_limit_check(org_invite_rate_limit_key, options).at_limit?
  end
end
