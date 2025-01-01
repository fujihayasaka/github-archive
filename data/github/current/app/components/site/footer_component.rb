# typed: true
# frozen_string_literal: true

class Site::FooterComponent < ApplicationComponent
  def initialize(can_toggle_site_admin_and_employee_status:, cookie_consent_enabled:, no_horizontal_padding: false, business_footer_enabled: true)
    @can_toggle_site_admin_and_employee_status = can_toggle_site_admin_and_employee_status
    @cookie_consent_enabled = cookie_consent_enabled
    @no_horizontal_padding = no_horizontal_padding
    @business_footer_enabled = business_footer_enabled
  end

  def can_toggle_site_admin_and_employee_status?
    @can_toggle_site_admin_and_employee_status
  end

  def cookie_consent_enabled
    @cookie_consent_enabled
  end

  def business_footer_enabled
    @business_footer_enabled
  end

  def footer_classes
    class_names(
      "footer pt-8 pb-6 f6 color-fg-muted",
       "p-responsive": !@no_horizontal_padding,
    )
  end

  def footer_container_classes
    "d-flex flex-justify-center flex-items-center flex-column-reverse flex-lg-row flex-wrap flex-lg-nowrap"
  end

  def footer_ul_classes
    "list-style-none d-flex flex-justify-center flex-wrap mb-2 mb-lg-0"
  end

  def footer_org_classes
    "d-flex flex-items-center flex-shrink-0 mx-2"
  end

  def should_show_community_forum_link?
    FeatureFlag.vexi.enabled?(:global_nav_reductive_user_menu, current_user, default: false)
  end
end
