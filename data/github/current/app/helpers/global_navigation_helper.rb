# typed: true
# frozen_string_literal: true

module GlobalNavigationHelper
  attr_reader :nav_breadcrumb
  extend T::Helpers

  ACTIONS_TO_LOG_MISSING_CRUMBS = %w[index show].freeze

  abstract!

  sig { abstract.returns(T.nilable(Repository)) }
  def current_repository; end

  # this should be nilable, but we can't use T.nilable because lots of other methods expect it to be non-nil
  sig { abstract.returns(T.untyped) }
  def current_user; end

  sig { abstract.returns(T::Boolean) }
  def logged_in?; end

  def set_default_nav_breadcrumb
    return unless automatically_set_breadcrumbs_for_request?
    return if defined? @nav_breadcrumb

    T.bind(self, ApplicationController)

    crumb_object = default_breadcrumb_object

    if crumb_object.present?
      crumb_options = { current_user: current_user }

      if crumb_object.is_a?(User)
        crumb_options[:private_profile_override] = staff_override_private_profile?
      end

      set_nav_breadcrumb ContextRegion::Factory.build(crumb_object, **crumb_options)
    end
  end

  def log_missing_global_navigation_crumbs
    return unless missing_crumb_logging_enabled?

    # if a breadcrumb has been set by this point, it's not considered missing
    return if defined? @nav_breadcrumb

    T.bind(self, ApplicationController)

    # record missing breadcrumbs in datadog for observability
    GitHub.dogstats.increment("missing_global_nav_crumb", tags: [
      "controller:#{controller_name}",
      "action:#{action_name}",
    ])
  end

  def default_breadcrumb_object
    return @default_breadcrumb_object if defined? @default_breadcrumb_object
    T.bind(self, ApplicationController)
    @default_breadcrumb_object = current_repository || find_owner_crumb_object
  end

  def find_owner_crumb_object
    T.bind(self, T.untyped)
    this_org = this_organization if respond_to?(:this_organization, true) && !this_organization.nil?
    current_org = current_organization if respond_to?(:current_organization, true) && !current_organization.nil?
    this_business = T.let(self.this_business, T.untyped) if respond_to?(:this_business, true) && self.this_business.present?

    return this_business if this_business
    return this_team if (this_org || current_org) && respond_to?(:this_team, true) && !this_team.nil?
    return this_org if this_org
    return current_org if current_org
    this_user if respond_to?(:this_user, true)
  end

  def set_nav_breadcrumb(crumb)
    return unless header_redesign_enabled?
    @nav_breadcrumb = crumb
  end

  # Sets a basic crumb object with just a static label and path,
  # useful for pages where the nav context is not tied to an object.
  def context_region_title(label, options = {})
    return unless header_redesign_enabled?
    options[:label] = label
    set_nav_breadcrumb(ContextRegion::BasicCrumb.new(nil, options))
  end

  # Create a preset for context crumbs that are reused in multiple areas of the codebase
  def context_region_preset(preset_name)
    return unless header_redesign_enabled?
    set_nav_breadcrumb(ContextRegion::Factory.preset(preset_name))
  end

  def disable_header_redesign
    @header_redesign_enabled = false
  end

  def header_redesign_enabled?
    return false unless logged_in?
    return @header_redesign_enabled if defined? @header_redesign_enabled # override this instance variable to disable the header on a per-controller basis
    true
  end

  def repos_header_redesign_enabled?
    return false unless logged_in?
    return @repos_header_redesign_enabled if defined? @repos_header_redesign_enabled

    @repos_header_redesign_enabled = header_redesign_enabled?
  end

  def automatically_set_breadcrumbs_for_request?
    return false unless header_redesign_enabled?
    return false unless valid_request_for_breadcrumbs?
    true
  end

  def valid_request_for_breadcrumbs?
    @valid_request_for_breadcrumbs ||= begin
      T.bind(self, ApplicationController)

      return false unless logged_in?
      return false if request.xhr?

      if FeatureFlag.vexi.enabled?("global_nav_request_check", current_user, default: false)
        # Skip for non-HTML formats (JSON, XML, SVG, etc.)
        return false unless request.format.html?
      end

      true
    end
  end

  def show_subnav?(hide_subnav: false)
    !hide_subnav
  end

  def context_crumb_path(crumb)
    return crumb.href if crumb.has_href?
    return "#" unless crumb.has_path?

    if crumb.path
      crumb.path
    else
      T.unsafe(self).send(crumb.path_name, *crumb.path_args) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    end
  end

  private

  def staff_override_private_profile?
    T.bind(self, ApplicationController)
    current_user&.site_admin? && params[:private_profile_override]
  end

  def eager_load_global_nav?
    return false unless logged_in?
    return @eager_load_global_nav if defined? @eager_load_global_nav
    @eager_load_global_nav = FeatureFlag.vexi.enabled_or_raise?(:eager_load_global_nav, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def react_global_create_menu?
    return false unless logged_in?
    return @react_global_create_menu if defined? @react_global_create_menu
    @react_global_create_menu = FeatureFlag.vexi.enabled_or_raise?(:react_global_create_menu, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def missing_crumb_logging_enabled?
    return false unless logged_in?
    return @missing_crumb_logging_enabled if defined? @missing_crumb_logging_enabled

    T.bind(self, ApplicationController)

    @missing_crumb_logging_enabled = automatically_set_breadcrumbs_for_request? &&
      ACTIONS_TO_LOG_MISSING_CRUMBS.include?(action_name) &&
      FeatureFlag.vexi.enabled?("log_missing_global_navigation_crumbs", current_user, default: false)
  end
end
