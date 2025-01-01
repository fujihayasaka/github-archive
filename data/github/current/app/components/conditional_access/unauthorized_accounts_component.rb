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
  # exclude_saml: Optional boolean to exclude SAML organizations from the unauthorized accounts list (default: false)
  def initialize(classes:, inner_classes: "Box-row p-1 m-1", container_classes: nil, icon_arguments: { mx: 1 }, tag: :div, resource_label:, return_to: nil, accounts: nil, cap_filter:, logging: false, group_saml: false, sort_by_name: false, exclude_saml: false)
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
    @exclude_saml = exclude_saml
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
    if !@group_saml && !exclude_saml_accounts?
      return unauthorized_accounts_by_policy
    end

    unauthorized_accounts_by_policy.except(:saml)
  end

  # Returns the unauthorized accounts to render in a unified SAML component.
  memoize def grouped_unauthorized_saml_targets
    if !@group_saml || exclude_saml_accounts?
      return []
    end

    targets = target_for(unauthorized_accounts_by_policy[:saml], :saml) || []
    return targets.sort_by { |target| target.name.downcase } if sort_by_name

    targets
  end

  ORGS_TO_DISPLAY = 3
  # Returns the organizations names to display in the unified SAML component.
  def saml_accounts_text
    text = safe_join(accounts_names_by_size) + " " + organizations_text + "."

    # if there is 1 other org and text length is <= 95, we can show all orgs
    return text unless other_orgs == 1 && text.length <= 95

    safe_join(accounts_names_by_size(show_all_orgs: true)) + " organizations."
  end

  def organizations_text
    if grouped_unauthorized_saml_targets.size > 3 || grouped_unauthorized_saml_targets.size == 3 && ORGS_TO_DISPLAY != 3
      return "and #{other_orgs} other #{"organization".pluralize(other_orgs)}"
    end

    "organization".pluralize(grouped_unauthorized_saml_targets.size)
  end

  def other_orgs
    grouped_unauthorized_saml_targets.size - ORGS_TO_DISPLAY
  end

  def accounts_names_by_size(show_all_orgs: false)
    names = grouped_unauthorized_saml_targets.map(&:name)
    short_text = names.size <= 3 || show_all_orgs

    org_names = short_text ? names : names[0...3]
    org_names.map.with_index do |name, index|
      next bold_tag(name) + union_type(names, index) if short_text

      bold_tag(name) + (index == org_names.size - 1 ? "" : ", ")
    end
  end

  def union_type(names, index)
    return "" if names.size == 1 || index == names.size - 1

    index == names.size - 2 ? " and " : ", "
  end

  def bold_tag(name)
    ActionController::Base.helpers.content_tag(:b, name)
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

  private

  def before_render
    super
    record_legacy_sso_banner_rendered if should_record_legacy_sso_banner_rendered?
  end

  def should_record_legacy_sso_banner_rendered?
    unauthorized_accounts_by_policy.key?(:saml) && unauthorized_accounts_by_policy[:saml].present?
  end

  def record_legacy_sso_banner_rendered
    return unless FeatureFlag.vexi.enabled?(:record_sso_banner_metrics, current_user, default: false)

    stat_key = "browser.events.sso_banner.legacy.global_banner_enabled"

    saml_accounts = unauthorized_accounts_by_policy[:saml]
    saml_targets = target_for(saml_accounts, :saml) || []
    saml_target_count = saml_targets.count

    return if saml_target_count.zero?

    GitHub.dogstats.increment(
      stat_key,
      tags: [
        "component:ConditionalAccess::UnauthorizedAccountsComponent",
        "resource_label:#{resource_label}",
        "saml_accounts_count:#{saml_target_count}",
      ]
    )
  end

  memoize def global_saml_banner_enabled?
    helpers.global_sso_banner_enabled_for_current_page?
  end

  memoize def exclude_saml_accounts?
    @exclude_saml || global_saml_banner_enabled?
  end
end
