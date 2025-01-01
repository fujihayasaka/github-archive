# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::SponsoringTabComponent < ApplicationComponent
  extend T::Sig
  include ApplicationComponent::Rescuable
  rescue_from_database_errors with: :nothing

  # organization - an Organization
  # is_billing_manager - Boolean indicating if the currently authenticated viewer is a billing manager of the
  #                      specified organization
  # is_org_member - Boolean indicating if the currently authenticated viewer is a member or admin of the specified
  #                 organization
  # link_classes - optional String of CSS classes to apply to the `<a>` tag
  def initialize(organization:, is_billing_manager: false, is_org_member: false, link_classes: nil)
    @organization = organization
    @is_billing_manager = is_billing_manager
    @is_org_member = is_org_member
    @link_classes = link_classes
  end

  memoize def url
    org_sponsoring_path(@organization)
  end

  def text
    "Sponsoring"
  end

  def tab_id
    "org-header-#{text.parameterize}-tab"
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: org_sponsoring_path(@organization),
      text: text,
      icon: "heart",
      link_classes: @link_classes,
      count: sponsoring_count,
      test_selector: "sponsoring-tab",
      tab_id: tab_id,
    ))
  end

  memoize def render?
    @organization.present? && GitHub.sponsors_enabled? && visible_to_viewer?
  end

  private

  # Private: How many organizations or developers is the organization sponsoring?
  #
  # Returns an integer.
  memoize def sponsoring_count
    @organization.sponsoring_count(include_private: org_member_or_billing_manager?)
  end

  # Private: How many organizations or developers has the organization sponsored in the past?
  #
  # Returns an integer.
  memoize def inactive_sponsoring_count
    @organization.inactive_sponsoring_count(include_private: org_member_or_billing_manager?)
  end

  sig { returns T::Boolean }
  def org_member_or_billing_manager?
    !!(@is_org_member || @is_billing_manager)
  end

  def visible_to_viewer?
    sponsoring_count.positive? || inactive_sponsoring_count.positive?
  end
end
