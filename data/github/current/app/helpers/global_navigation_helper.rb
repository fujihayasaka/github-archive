# typed: true
# frozen_string_literal: true

module GlobalNavigationHelper
  attr_reader :nav_breadcrumb
  extend T::Sig
  extend T::Helpers

  abstract!

  sig { abstract.returns(T.nilable(Repository)) }
  def current_repository; end

  # this should be nilable, but we can't use T.nilable because lots of other methods expect it to be non-nil
  sig { abstract.returns(T.untyped) }
  def current_user; end

  sig { abstract.returns(T::Boolean) }
  def logged_in?; end

  def set_default_nav_breadcrumb
    return unless default_nav_breadcrumbs_enabled?
    return if defined? @nav_breadcrumb
    T.bind(self, ApplicationController)

    crumb_object = default_breadcrumb_object

    if crumb_object.present?
      crumb_options = { current_user: current_user }

      if crumb_object.is_a?(User)
        crumb_options[:private_profile_override] = staff_override_private_profile?
      end

      set_nav_breadcrumb ContextRegion::Factory.build(crumb_object, **crumb_options)
    elsif crumb_object.nil? && Rails.env.development?
      # to help find where this context is missing, we put some info in the context region
      context_region_title "Missing context: #{controller_name}##{action_name}"
    end
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
    return this_user if respond_to?(:this_user, true)
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

  def default_nav_breadcrumbs_enabled?
    return false unless valid_request_for_breadcrumbs?
    return false unless header_redesign_enabled?
    true
  end

  def valid_request_for_breadcrumbs?
    T.bind(self, ApplicationController)
    return false if request.xhr?
    true
  end

  private

  def staff_override_private_profile?
    T.bind(self, ApplicationController)
    current_user&.site_admin? && params[:private_profile_override]
  end

  def eager_load_global_nav?
    return false unless logged_in?
    return @eager_load_global_nav if defined? @eager_load_global_nav
    @eager_load_global_nav = GitHub.flipper[:eager_load_global_nav].enabled?(current_user)
  end

  def react_global_create_menu?
    return false unless logged_in?
    return @react_global_create_menu if defined? @react_global_create_menu
    @react_global_create_menu = GitHub.flipper[:react_global_create_menu].enabled?(current_user)
  end
end
