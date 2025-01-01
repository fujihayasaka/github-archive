# typed: strict
# frozen_string_literal: true

class Organizations::MemberRequests::AddonActionsComponent < ApplicationComponent
  include ApplicationComponent::Rescuable
  rescue_from StandardError, with: :nothing

  SupportedAddonFeatures = T.type_alias { MemberFeatureRequest::Feature::CopilotForBusiness }

  sig { returns(SupportedAddonFeatures) }
  attr_reader :feature

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(User) }
  attr_reader :user

  sig { params(feature: SupportedAddonFeatures, organization: Organization, user: User).void }
  def initialize(feature:, organization:, user:)
    @feature = T.let(feature, SupportedAddonFeatures)
    @organization = T.let(organization, Organization)
    @user = T.let(user, User)
  end

  sig { returns(T::Boolean) }
  def primary_cta_form_submission?
    primary_cta_detail[:form].present?
  end

  sig { returns(T::Boolean) }
  def show_enterprise_request_button?
    copilot_organization.can_request_copilot_from_enterprise?(user)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def primary_cta_detail
    case feat = feature
    when MemberFeatureRequest::Feature::CopilotForBusiness
      copilot_for_business_addon_detail
    else
      T.absurd(feat)
    end
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  memoize def secondary_cta_detail
    case feat = feature
    when MemberFeatureRequest::Feature::CopilotForBusiness
      {
        text: "See how it works",
        url: "https://www.youtube.com/watch?v=IqXNhakuwVc",
        data: analytics_click_attributes(
          category: "requests_from_members_page",
          action: "click_to_watch_#{feature}_how_it_works_video",
          label: "ref_cta:see_how_it_works; ref_loc:requests_from_members_business_add_on"
        )
      }
    else
      T.absurd(feat)
    end
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def copilot_for_business_addon_detail
    if copilot_organization.copilot_enabled?
      {
        text: "Review access requests",
        url: settings_org_copilot_seat_management_path(organization),
        data: analytics_click_attributes(
          category: "requests_from_members_page",
          action: "click_to_review_access_requests",
          label: "ref_cta:review_access_requests; ref_loc:requests_from_members_business_add_on",
        ),
      }
    elsif copilot_organization.can_enable_org_to_assign_seats?(user)
      {
        text: "Allow this organization to assign seats",
        url: enterprise_copilot_permission_to_assign_seats_path(organization.business, organization_id: organization.display_login),
        form: { method: :put },
        data: analytics_click_attributes(
          category: "assign_seats_cta",
          action: "click_to_allow_to_assign_seats",
          label: "ref_cta:allow_to_assign_seats; ref_loc:requests_from_members_business_add_on"
        )
      }
    else
      {
        text: "Buy #{Copilot.business_product_name}",
        url: copilot_business_signup_organization_payment_path(org: organization),
        data: analytics_click_attributes(
          category: "requests_from_members_page",
          action: "click_to_buy_#{feature}",
          label: "ref_cta:buy_#{feature}; ref_loc:requests_from_members_business_add_on"
        ),
      }
    end
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    Copilot::Organization.new(organization)
  end
end
