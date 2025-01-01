# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module UsersHelper
  include FeatureFlagHelper
  include ActionView::Helpers::UrlHelper
  include GitHub::Memoizer

  ALLOWED_MOBILE_TABS = %w(overview repositories stars followers following projects)
  MAX_SPONSORS_TO_DISPLAY = 14

  def show_block_button?(is_viewer:)
    GitHub.user_abuse_mitigation_enabled? && !is_viewer
  end

  # Public: Get Hydro click-tracking attributes for use in a link in the 'Activity overview'
  # section of the user profile.
  #
  # selected_org_database_id - database ID of the Organization that's currently applied as a filter
  #                            for the 'Activity overview' section; Integer, optional
  # path - URL the link will take you to; String, URI, or GraphQL URL
  # type - the type of record the link will take you to; Symbol
  #        choose from :ORGANIZATION, :REPOSITORY, :TEAM, or :UNKNOWN
  #        defaults to :UNKNOWN if nil
  #
  # Returns a Hash.
  def activity_overview_link_hydro_attrs(selected_org_database_id:, path:, type:)
    hydro_click_tracking_attributes(
      "user_profile.highlights_click",
      scoped_org_id: selected_org_database_id,
      target_type: type ? type : :UNKNOWN,
      target_url: path.to_s,
    )
  end

  # Public: Get Hydro click-tracking attributes for use in an organization filter link in the
  # 'Activity overview' section of the user profile.
  #
  # selected - whether the link being clicked represents the currently selected organization
  #            filter; Boolean
  # selected_org_database_id - database ID of the Organization that's currently applied as a filter
  #                            for the 'Activity overview' section; Integer, optional; not
  #                            necessarily the same as the Organization represented in the link
  #                            being clicked
  # path - URL the link will take you to; String
  #
  # Returns a Hash.
  def activity_overview_org_filter_hydro_attrs(selected: false, selected_org_database_id:, path:)
    if selected
      {}
    else
      activity_overview_link_hydro_attrs(selected_org_database_id: selected_org_database_id,
                                         path: path, type: :ORGANIZATION)
    end
  end

  # Public: Get the URL to filter contributions shown on the user profile by the
  # given organization. Preserves the date filtering.
  #
  # base_path - the user page you're starting from, e.g., "/defunkt"
  # org - an organization login as a String
  # selected - Boolean; is the given organization already the chosen filter?
  #
  # Returns a String.
  def user_profile_org_filter_path(base_path:, org:, selected: false)
    parts = ["tab=overview"]
    parts << "org=#{org}" unless selected
    parts << "from=#{params[:from]}" if params[:from]
    parts << "to=#{params[:to]}" if params[:to]
    query = parts.join("&")
    "#{base_path}?#{query}"
  end

  def follow_button(user, classes: "btn btn-sm", make_primary: false, style: nil, data: {})
    return if user.private_profile_for?(current_user) && !user.followed_by?(current_user)

    render partial: "users/follow_button", locals: {
      classes: classes,
      style: style,
      make_primary: make_primary,
      user: user,
      data: data,
    }
  end

  def vcard_item(name, *args, &block)
    if block_given?
      value = capture(&block)
      options = args.first
    else
      value, options = args
    end
    return nil if value.blank? || name.blank?

    icon = options.delete(:icon) || octicon(name)
    options = options.merge(class: "vcard-detail pt-1 #{options[:class]}")

    if options[:show_title]
      options = options.merge(title: value)
      options.delete(:show_title)
      content_tag(:li, icon + value, options)
    else
      content_tag(:li, icon + value, options)
    end
  end

  def notices_for(user)
    safe_join(user.notices_for_dashboard.map { |name| render_notice(name) })
  end

  def render_notice(name)
    case name.to_sym
    when :coupon_will_expire
      render partial: "notices/coupon_will_expire"
    when :org_newbie
      render partial: "notices/org_newbie"
    else
      nil
    end
  end

  # Creates an HTML-Safe link to a User's profile page.
  #
  # user - A User
  #
  # Returns an HTML-Safe String.
  def link_to_user(user)
    link_to user.name, user_path(user)
  end

  # Format a number (watching, starred, follower, following) for display on the
  # user profile page. This is just a shortcut for `number_to_human` with the
  # appropriate formatting options set.
  #
  # count - The Integer to format.
  #
  # Examples
  #
  #   social_count(123) # => "123"
  #   social_count(1_234) # => "1.2k"
  #   social_count(123_456) # => "123k"
  #   social_count(1_234_567) # => "1.2m"
  #
  # Returns a formatted String.
  def social_count(count)
    precision = count.between?(100_000, 999_999) ? 0 : 1
    number_to_human(count, precision: precision, significant: false, units: { thousand: "k", million: "m", billion: "b" }, format: "%n%u")
  end

  # Public: Build a page title for a user followers page
  #
  # login: String login of the user
  # name: String profile name of the user
  # is_viewer: Boolean indicating whether the viewer is the user
  #
  # Returns a String
  def user_followers_title(login:, name:, is_viewer:)
    if is_viewer
      "Your Followers"
    else
      profile_page_title(login: login, name: name, section: "Followers")
    end
  end

  # Public Build a page title for a user following page
  #
  # login: String login of the user
  # name: String profile name of the user
  # is_viewer: Boolean indicating whether the viewer is the user
  #
  # Returns a String
  def user_following_title(login:, name:, is_viewer:)
    if is_viewer
      "Who You’re Following"
    else
      profile_page_title(login: login, name: name, section: "Following")
    end
  end

  def user_achievements_title(login:, name:, is_viewer: false)
    if is_viewer
      "Your Achievements"
    else
      profile_page_title(login: login, name: name, section: "Achievements")
    end
  end

  def user_projects_title(login:, name:, is_viewer:)
    if is_viewer
      "Your projects"
    else
      profile_page_title(login: login, name: name, section: "Projects")
    end
  end

  def user_packages_title(login:, name:, is_viewer:)
    if is_viewer
      "Your Packages"
    else
      profile_page_title(login: login, name: name, section: "Packages")
    end
  end

  def user_stars_title(login:, name:, is_viewer:)
    if is_viewer
      "Your Stars"
    else
      profile_page_title(login: login, name: name, section: "Starred")
    end
  end

  def user_sponsoring_title(login:, name:, is_viewer:)
    if is_viewer
      "Who You're Sponsoring"
    else
      profile_page_title(login: login, name: name, section: "Sponsoring")
    end
  end

  # Alert strings to display to site admins on a User's profile page.
  #
  # this_user - A User whose profile is currently being viewed
  #
  # Returns an HTML-Safe String if alerts exist or nil otherwise.
  def site_admin_alerts
    alerts = []
    alerts << "suspended" if this_user.suspended?
    alerts << safe_join(["flagged ", content_tag(:strong, "spammy")]) if this_user.spammy?
    alerts.empty? ? nil : (safe_join(alerts, " and ") << ".")
  end

  def show_admin_alerts?
    current_user.try(:site_admin?) || GitHub.show_user_profile_alerts?
  end

  def profile_page_meta_description(login:, profile_bio:, public_repo_count:)
    meta_description = I18n.t("profiles.meta_description",
                              username: login,
                              count: public_repo_count)
    opengraph_description(login, profile_bio, meta_description)
  end

  def profile_page_title(login:, name:, section: nil)
    prefix = if name.present?
      "#{login} (#{name})"
    else
      "#{login}"
    end
    suffix = " / #{section}" if section.present?
    "#{prefix}#{suffix}"
  end

  def show_upgrade_user_menu?
    return false if GitHub.enterprise?
    return false if current_user.is_enterprise_managed?
    return false if current_user.plan.pro? && (!current_user.organizations.any? || current_user.organizations.all? { |org| org.plan.paid? })
    true
  end

  def show_start_a_trial_url?
    return false if GitHub.enterprise?
    return false if current_user.is_enterprise_managed?
    return false if current_user.businesses(membership_type: :admin).any?
    return false if current_user.owned_organizations.where(plan: GitHub::Plan.business_plus.name).any?
    true
  end

  memoize def your_enterprise_user_menu_slug
    if current_user.is_enterprise_managed? && current_user.enterprise_managed_business.present?
      current_user.enterprise_managed_business.slug
    elsif GitHub.single_business_environment?
      GitHub.global_business.slug
    end
  end

  # Should the "Enterprise settings" link be shown?
  #
  # Returns true if it's GHES and the current user is an owner
  # of the global enterprise account.
  #
  # Returns Boolean
  def show_enterprise_settings_user_menu?
    return false unless GitHub.single_business_environment?
    return true if GitHub.global_business.owner?(current_user)
    false
  end

  def user_menu_settings_name
    show_enterprise_settings_user_menu? ? "User settings" : "Settings"
  end

  # Should the "Your enterprises" link be shown?
  #
  # Returns false for GHES or EMU user since they can only be associated with a single enterprise,
  # and true for GitHub.com (non-EMU) user.
  #
  # Returns Boolean
  def show_your_enterprises_user_menu?
    return false if your_enterprise_user_menu_slug.present?
    true
  end

  # Should the "Your enterprise" link be shown?
  #
  # Returns true if EMU or if it's GHES and the current user is not an owner of
  # the global enterprise account.
  #
  # Returns Boolean
  def show_your_enterprise_user_menu?
    return false unless your_enterprise_user_menu_slug.present?
    return true if current_user.is_enterprise_managed?
    !GitHub.global_business.owner?(current_user)
  end

  def show_pending_invitations_indicator?
    return if GitHub.enterprise?
    return @show_pending_invitations_indicator if defined?(@show_pending_invitations_indicator)

    @show_pending_invitations_indicator ||= begin
      has_org_invites = OrganizationInvitation
        .includes(:organization)
        .pending
        .where(invitee_id: current_user.id)
        .reject { |invite| invite.organization.nil? || invite.organization.spammy? || invite.organization.deleted? }
        .any?
      has_repo_invites = RepositoryInvitation
        .includes(repository: :owner)
        .excluding_expired
        .where(invitee_id: current_user.id)
        .reject { |invite| invite.repository.owner.nil? || invite.repository.owner.spammy? }
        .any?

      has_org_invites || has_repo_invites
    end
  end
end
