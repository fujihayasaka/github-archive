# typed: true
# frozen_string_literal: true

class ConditionalAccess::UnauthorizedAccountsComponent < ApplicationComponent
  include ConditionalAccessHelper

  attr_reader :tag, :classes, :inner_classes, :container_classes, :icon_arguments, :resource_label, :return_to, :cap_filter, :group_saml, :sort_by_name

  # classes: CSS classes that style the rendered template
  # container_classes: CSS classes that style the container that wraps the rendered template. If there are no unauthorized accounts, the container is not rendered
  # resource_label: Conditional Access Policy (CAP) protected resources i.e codespaces, repositories, notifications
  # cap_filter: the ConditionalAccess::Web::Filter that will perform the filtering
  # accounts: Optional set of Users/Organizations to filter. If none is passed, current_user.resources_for_cap_filter will be used.
  #       Note that we can't call current_user here, only at render time:
  #       ViewComponent::Base::ViewContextCalledBeforeRenderError: `helpers` can only be called at render time.
  # logging: Optional boolean to enable logging of unauthorized accounts
  # group_saml: Optional boolean to group SAML organizations into a unified component (default: false)
  # sort_by_name: Optional boolean to sort SAML organizations by name (default: false)
  def initialize(classes:, inner_classes: "Box-row p-1 m-1", container_classes: nil, icon_arguments: { mx: 1 }, tag: :div, resource_label:, return_to: nil, accounts: nil, cap_filter:, logging: false, group_saml: false, sort_by_name: false)
    @classes = classes
    @tag = tag
    @inner_classes = inner_classes
    @container_classes = container_classes
    @icon_arguments = icon_arguments
    @resource_label = resource_label
    @return_to = return_to
    @cap_filter = cap_filter
    @accounts = accounts
    @group_saml = group_saml
    @logging = logging
    @sort_by_name = sort_by_name
  end

  # Uses the Conditional Access Policy framework filter object to compute unauthorized accounts.
  #
  # Returns Hash of Users/Organizations grouped by Conditional Access Policy (CAP) policies. Example {:saml => [org1, org2]}
  def unauthorized_accounts_by_policy
    return @unauthorized_accounts_by_policy if defined?(@unauthorized_accounts_by_policy)

    @accounts ||= current_user&.resources_for_cap_filter
    unauthorized_accounts = cap_filter.unauthorized(@accounts).by_policy
    log_unauthorized_accounts(unauthorized_accounts) if @logging

    @unauthorized_accounts_by_policy = unauthorized_accounts
  end

  # Returns the unauthorized accounts to render in individual banner components.
  memoize def unauthorized_accounts_for_banner
    if !@group_saml
      return unauthorized_accounts_by_policy
    end

    unauthorized_accounts_by_policy.except(:saml)
  end

  # Returns the unauthorized accounts to render in a unified SAML component.
  memoize def grouped_unauthorized_saml_targets
    if !@group_saml
      return []
    end

    targets = target_for(unauthorized_accounts_by_policy[:saml], :saml) || []
    return targets.sort_by { |target| target.name.downcase } if sort_by_name

    targets
  end

  ORGS_TO_DISPLAY = 3
  # Returns the organizations names to display in the unified SAML component.
  def saml_accounts_text
    orgs_names_to_display + " organization".pluralize(grouped_unauthorized_saml_targets.size - ORGS_TO_DISPLAY) + "."
  end

  def orgs_names_to_display
    if grouped_unauthorized_saml_targets.size > ORGS_TO_DISPLAY
      safe_join([
        content_tag_text(:b, grouped_unauthorized_saml_targets.first(ORGS_TO_DISPLAY).map(&:name).join(", ")),
        content_tag_text(:span, ", and #{grouped_unauthorized_saml_targets.size - ORGS_TO_DISPLAY} other ")
      ])
    else
      content_tag_text(:b, grouped_unauthorized_saml_targets.map(&:name).to_sentence)
    end
  end

  def content_tag_text(tag, text)
    ActionController::Base.helpers.content_tag(tag, text)
  end

  # Temporary logs to get data on the number of unauthorized accounts for the notifications page
  # We will evaluate if removing this once we have a better understanding of the data and if it's useful
  # https://github.com/github/notifications-experience/issues/506
  def log_unauthorized_accounts(unauthorized_accounts)
    display_count = unauthorized_accounts.sum do |policy, accounts|
      target_for(accounts, policy).count
    end
    return if display_count.zero?

    GitHub.dogstats.distribution("cap.unauthorized_accounts", display_count, tags: ["resource_label:#{resource_label}"])
    GitHub.logger.info(
      "Generating unauthorized accounts",
      "code.namespace": "ConditionalAccess::UnauthorizedAccountsComponent",
      "code.function": "unauthorized_accounts_by_policy",
      "gh.resource.label": resource_label,
      "gh.user.id": current_user.id,
      "gh.user.login": current_user.display_login,
      "gh.unauthorized_accounts.return_to": return_to,
      "gh.unauthorized_accounts.size": display_count,
    )
  end
end
