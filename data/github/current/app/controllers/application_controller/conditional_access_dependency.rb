# typed: false
# frozen_string_literal: true

# Conditional access controller concern.
#
# Shares functionality used by features that provide conditional access
# to resources, such as external identity session enforcement or IP allow list
# enforcement.
module ApplicationController::ConditionalAccessDependency
  extend ActiveSupport::Concern

  included do
    helper_method :cap_filter
    helper_method :cap_view_filter
  end

  # rubocop:disable GitHub/DoNotInstantiatePlatformObjects
  def cap_filter
    @conditional_access_filter ||= ConditionalAccess::Web::Filter.new(self)
  end

  def cap_enforcer
    @conditional_access_enforcer ||= ConditionalAccess::Web::Enforcer.new(self)
  end

  def cap_view_filter
    @cap_view_filter ||= ConditionalAccess::View::Filter.new(self)
  end
  # rubocop:enable GitHub/DoNotInstantiatePlatformObjects


  # Public: The Organization or Business in the context of the endpoint that
  # is responsible for determining conditional access to the resource.
  #
  # Returns an Organization, Business, or nil.
  def target_for_conditional_access
    message = <<~MSG.squish
      #{self.class.name} is missing `#resource_for_conditional_access`
      and `#target_for_conditional_access`. Commonly called RFCA and TFCA.

      See [the hub](https://thehub.github.com/epd/engineering/products-and-services/dotcom/cap/cookbook/#resource-for-conditional-access-rfca--target-for-conditional-access-tfca)
      for the guidelines on how to implement these methods.

      Reach out to #authorization if you have questions!
    MSG
    exception = NotImplementedError.new message
    exception.set_backtrace(caller)

    if Rails.env.production?
      Failbot.report!(exception)
    else
      raise exception
    end
  end

  # Public: Controller action filter to enforce whether any conditional access
  # checks that apply to this request are satisfied.
  #
  # Returns nothing.
  def perform_conditional_access_checks
    GitHub.tracer.in_span("perform_conditional_access_checks", kind: :internal) do |span|
      span.add_attributes(
          GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/conditional_access",
          "code.function" => __method__.to_s,
          "code.namespace" => self.class.name
      )

      resource = self.respond_to?(:resource_for_conditional_access, true) ? self.resource_for_conditional_access : self
      next unless cap_enforcer.enforce_conditional_access_policies(resource) == :ok

      # See app/controllers/application_controller/external_sessions_dependency.rb
      require_active_external_identity_session if require_active_external_identity_session?
    end
  end

  # safe_target_for_conditional_access is the gatekeeper for target_for_conditional_access.
  # This method makes sure that target_for_conditional_access complies with the contract.
  #
  # This is a duplicate of Enforcer#safe_target_for_conditional_access
  # to avoid breaking SAML/IPAllowlist. Can be removed when SAML/IP Allowlist is migrated
  # to CAP framework.
  #
  # TODO: remove when SAML/IP Allowlist policies are migrated to Conditional Access Policy Framework (CAP)
  #
  # The contract is:
  # - return the owner of the resource, so long it's one of the accepted types [User, Organization, Business]
  # - indicate the circumstances in which there is no target for enforcement by returning :no_target_for_conditional_access
  #
  # this method should never be overridden by includers
  def safe_target_for_conditional_access
    resource = self.respond_to?(:resource_for_conditional_access, true) ? self.resource_for_conditional_access : self
    cap_enforcer.target_provider.target(resource)
  end

  # Only enforce IP allow list CAP when the environment supports IP allow lists
  def ip_allowlist_enforceable
    GitHub.ip_allowlists_available? ? :yes : :no
  end

  # Only enforce external conditional access policy where the environment supports IP allow lists
  def external_conditional_access_policy_enforceable
    GitHub.idp_cap_available? ? :yes : :no
  end
end
