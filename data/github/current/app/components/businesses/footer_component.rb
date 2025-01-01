# typed: true
# frozen_string_literal: true

class Businesses::FooterComponent < ApplicationComponent
  extend T::Sig
  include BusinessesHelper

  sig { returns(T.nilable(User)) }
  def current_user
    super
  end

  def initialize(repository:, business_footer_enabled: true)
    @repository = repository
    @business_footer_enabled = business_footer_enabled
  end

  memoize def business
    get_business
  end

  def show_business_footer?
    return false unless @business_footer_enabled
    return true if GitHub.single_business_environment? && GitHub.global_business
    return false unless @repository&.has_business_owner? if @repository
    return false unless logged_in?
    return false unless business
    return true if business.footer_links.any? && should_render_footer_links?

    false
  end

  def should_render_footer_links?
    current_user&.is_business_member?(business.id) || @repository&.organization&.user_is_outside_collaborator?(current_user&.id)
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

  private

  def get_business
    # Always show footer on GitHub Enterprise
    return GitHub.global_business if GitHub.single_business_environment?
    return @repository&.owner&.business if @repository
    current_business
  end
end
