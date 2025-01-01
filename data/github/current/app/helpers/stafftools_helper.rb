# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module StafftoolsHelper
  include TextHelper
  include OcticonsHelper
  include AuditLogHelper
  include ActionView::Helpers::UrlHelper
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::NumberHelper
  include Stafftools::AccessControlHelper

  def show_sponsors_section_on_stafftools_user_page?(account)
    return false unless GitHub.sponsors_enabled?
    return true if account.sponsors_listing
    account.eligible_for_nudging_to_sign_up_for_sponsors?
  end

  def progress_bar(percent, options = {})
    precision = options.fetch(:precision, 0)
    percentage_text = if options[:percentage]
      content_tag(:span, number_to_percentage(percent, precision: precision), class: "percent")
    else
      nil
    end

    content_tag(:span,
      safe_join([content_tag(:span,
        GitHub::HTMLSafeString::NBSP,
        class: "progress",
        style: "width: #{percent}%",
      ),
      percentage_text]),
      class: "progress-bar",
    )
  end

  def stafftools_audit_log_query(target)
    keys = if target.business?
      %w{business_id}
    else
      result = %w{actor_id user_id}
      result << "org_id" if target.organization?
      result
    end

    if driftwood_ade_query?(T.unsafe(self).current_user)
      "webevents | where (#{keys.reverse.map { |key| "#{key} == #{target.id}" }.join(" or ")})"
    else
      query = keys.reverse.map { |k| "#{k}:#{target.id}" }.join " OR "
      "(#{query})"
    end
  end

  # Represent an Array of organization/team members in a standard copyable
  # text format that is suitable for being used from stafftools via a copy
  # button or something similar.
  #
  # members - The Array of organization or team members to be represented in the
  #           standard copyable format.
  #
  # Example
  #   members_as_copyable_text([izuzak, jdennes])
  #   # => "@izuzak - Ivan Žužak\n@jdennes - James Dennes\n"
  #
  # Returns a String that contains copyable text that represents the
  # organization/team members where each line uses the format:
  #   @<login> - <profile name>
  def members_as_copyable_text(members)
    members.each.map do |member|
      entry = "@#{member.login}".dup
      entry << " - #{member.safe_profile_name}" unless member.profile_name.blank?
      entry << "\n"
    end.join("")
  end

  # Get the time at which an account was flagged spammy.
  #
  # account - The User, Organization, or Business.
  #
  # Returns Time
  def spam_flag_timestamp(account)
    if account.spammy?
      id_field = account.is_a?(Business) ? "business_id" : "user_id"
      options = {
        phrase: "action:staff.mark_as_spammy #{id_field}:#{account.id}",
        current_user: T.unsafe(self).current_user,
      }
      if driftwood_ade_query?(T.unsafe(self).current_user)
        options[:phrase] =
          "webevents | where action == 'staff.mark_as_spammy' and #{id_field} == #{account.id}"
      end
      query = Audit::Driftwood::Query.new_stafftools_query(options)
      results = AuditLogEntry.new_from_array(query.execute)

      results.first.created_at if results.first
    end
  end

  # Public: Auto-link any links in the spammy reason
  #
  # Returns "No reason given" if given a blank reason.
  # Else, returns the autolinked reason
  def autolink_spammy_reason(reason)
    return "No reason given" if reason.blank?
    T.unsafe(self).auto_link(reason, mode = :urls, link_attr = nil, skip_tags = nil)
  end

  # Get the "clear cache" URL for a given URL, for use from site admin pages, by
  # adding skipmc=1 and _timeout=clear to the query string params of the URL.
  #
  # url - String representing the URL for which a "clear cache" URL should be
  #       generated.
  #
  # Example
  #   stafftools_clear_cache_url("https://gh.ent/trending?since=daily")
  #   # => "https://gh.ent/trending?_timeout=clear&since=daily&skipmc=1"
  #
  # Returns a String that is the "clear cache" URL for the given URL.
  def stafftools_clear_cache_url(url)
    parsed_url = Addressable::URI.parse(url)
    parsed_url.query_values = (parsed_url.query_values || {}).merge({
      skipmc:   "1",
      _timeout: "clear",
    })
    parsed_url.normalize.to_s
  end

  STAFFTOOLS_NOT_AUTHORIZED_HTML = GitHub::HTMLSafeString.make %Q[You're not authorized to perform this action in stafftools. To request access, please <a href="https://thehub.github.com/engineering/security/entitlements/stafftools-entitlements">follow the steps on The Hub</a>.]
  def stafftools_not_authorized_html
    STAFFTOOLS_NOT_AUTHORIZED_HTML
  end

  def stafftools_not_authorized_text
    "You're not authorized to use this feature. To request access, open an issue in the github/security-iam repo."
  end

  # Parse controller and action from a given path.
  #
  # path - String representing the path in the app
  #
  # Returns Hash.
  def parse_action(path)
    accessing = Rails.application.routes.recognize_path(path)
    # Convert controller to camel case from snake case
    # e.g. "stafftools/user_assets" => "Stafftools::UserAssetsController"
    controller = accessing[:controller].camelize + "Controller"
    { controller: controller, action: accessing[:action] }
  end

  # These methods are wrappers around the linked_to and button_to methods
  # to conditionally check role based access to a feature and obfuscate
  # or disable that content if permissions are not met
  def stafftools_selected_link_to(*args, &block)
    controller_and_action = parse_action(args[1])
    if stafftools_action_authorized?(controller_and_action)
      T.unsafe(self).selected_link_to(*args, &block)
    end
  end

  def stafftools_button_to(*args, &block)
    controller_and_action = parse_action(args[1])
    if stafftools_action_authorized?(controller_and_action)
      T.unsafe(self).button_to(*args, &block)
    else
      # Unfortunately this completely disables the button, making the aria useless.
      # We could potentially return a button wrapped in a div which holds the tooltip otherwise
      # we could just remove the aria-label and tooltip classes
      args[2] = args[2].merge({ class: " disabled tooltipped tooltipped-nw", disabled: true, "aria-label": stafftools_not_authorized_text }) { |_key, existing, addon| existing + addon }
      T.unsafe(self).button_to(*args, &block)
    end
  end

  # Public: Can the current viewer search the audit log in stafftools?
  #
  # Returns a Boolean.
  def viewer_can_search_audit_log?
    Stafftools::AccessControl.authorized?(
      T.unsafe(self).current_user, {
        controller: "Stafftools::SearchController",
        action: "audit_log",
      }
    )
  end

  # Public: Does the associated user have external identities to link to?
  #
  # Returns a Boolean.
  def show_external_identities?(user)
    user.external_identities.preload(provider: :target).reject { |ei| ei.provider&.target.nil? }.any?
  end

  # Public: Get a link to the user's external identities.
  #
  # If this user belongs to an environment with 1:1 user:external_identity
  # enforcement return a link to the user's first external identity. Otherwise
  # return a link to the user's security page to view all identities.
  #
  # Returns String
  def get_external_identities_link(user)
    if user.is_enterprise_managed? || GitHub.global_business&.enterprise_server_scim_enabled?
      path = Rails.application.routes.url_helpers.stafftools_enterprise_external_identity_path \
        user.external_identities.first.provider.target,
        user.display_login
      link_to "External Identity linked to the Provider", path
    elsif user.external_identities.any?
      link_to \
        "View all External Identities",
        Rails.application.routes.url_helpers.stafftools_user_security_path(user)
    end
  end

  # Public: Generates url/string for repository based on repository id
  #
  # Returns repository URL.
  def link_to_nwo_from_repository_id(id)
    ActiveRecord::Base.connected_to(role: :reading) do
      repo = Repositories::Public.find_active!(id)
      nwo = repo.name_with_owner
      link_to(nwo, repo.permalink, target: :blank)
    end
  rescue ActiveRecord::RecordNotFound => e
    "No repository found"
  end

  # Public: Returns any extra information about an account's plan around
  # trials or upcoming changes
  #
  # Returns a string (possibly empty)
  def account_plan_extra_info(account)
    cloud_trial = Billing::EnterpriseCloudTrial.new(account)

    if cloud_trial.active?
      "(trial expiring #{T.must(cloud_trial.expires_on).strftime("%b %-d %Y")})"
    elsif account.plan.name == GitHub::Plan::FREE && cloud_trial.ever_been_in_trial? && cloud_trial.expired?
      expired_on_copy = cloud_trial.expires_on.present? ? " that expired on #{T.must(cloud_trial.expires_on).strftime("%b %-d %Y")}" : ""
      "(was on Enterprise Cloud Trial#{expired_on_copy})"
    elsif account.pending_cycle.has_changes?(including_free_trials: false)
      "(change pending)"
    else
      ""
    end
  end

  # Public: Returns the enterprise-web admin URL for a given enterprise-web business
  #
  # Returns a string
  def enterprise_web_business_url(enterprise_web_business_id)
    "#{GitHub.enterprise_web_admin_url}/staff/businesses/#{enterprise_web_business_id}"
  end

  # Public: handles the possibility of negative file sizes that number_to_human size doesn't format well
  #
  # Returns a string
  def formatted_usage_breakdown(usage_data)
    human_readable = number_to_human_size(usage_data.abs)
    usage_data.negative? ? "-#{human_readable}" : human_readable
  end

  # Public: Checks for mismatch between billed aggregation and the summed events
  #
  # Returns a string
  def mismatched_aggregation_and_breakdown?(usage)
    usage.total_usage_in_bytes != usage.sum_aggregated_events
  end

  def visibility_octocon(visibility)
    symbol = visibility == "public" ? "repo" : "lock"
    octicon(symbol)
  end

  def bool_to_icon(bool)
    if bool
      octicon("check", class: "color-fg-success")
    else
      octicon("x", class: "color-fg-danger mr-1")
    end
  end
end
