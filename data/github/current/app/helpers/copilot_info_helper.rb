# typed: strict
# frozen_string_literal: true

module CopilotInfoHelper
  include GitHub::Memoizer
  include GitHub::ResilienceMixin
  include MemberFeatureRequestsHelper

  extend T::Helpers

  requires_ancestor { ApplicationController }

  class CodeView < T::Enum
    enums do
      Blame = new("blame")
      Edit = new("edit")
      Preview = new("preview")
    end
  end

  sig { params(view: CodeView, org: T.nilable(Organization)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def copilot_info_payload(view, org = nil)
    return nil unless user = current_user
    return nil if user.is_enterprise_managed?
    return nil unless GitHub.billing_enabled?
    return nil if org&.delegate_billing_to_business?

    copilot_access_info = copilot_user_access_info_payload(user, org)
    return nil unless show_copilot_popover?(user, org, copilot_access_info)

    instrument_popover_viewed(view, org)

    {
      documentationUrl: get_copilot_docs_url,
      notices: {
        codeViewPopover: code_view_popover_payload(user, org),
      },
      userAccess: copilot_access_info,
    }
  end

  private

  sig { params(user: User, org: T.nilable(Organization)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def copilot_user_access_info_payload(user, org = nil)
    with_database_error_fallback(fallback: nil) do
      {
        hasSubscriptionEnded: !!current_copilot_user_v2&.has_subscription_ended?,
        orgHasCFBAccess: !!(org && Copilot::Organization.new(org).has_copilot_for_business?),
        userHasCFIAccess: !!current_copilot_user_v2&.has_ci_access?,
        userHasOrgs: user.organizations.any?,
        userIsOrgAdmin: !!org&.adminable_by?(user),
        userIsOrgMember: !!org&.member?(user),
        business: copilot_business,
        featureRequestInfo: feature_request_info_payload(MemberFeatureRequest::Feature::CopilotForBusiness, user, org),
      }
    end
  end

  sig { params(user: User, org: T.nilable(Organization), copilot_access_info: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Boolean) }
  def show_copilot_popover?(user, org, copilot_access_info)
    return false if copilot_access_info.nil?
    return false if user_dismissed_popover?(user, org)
    return false if copilot_already_provided?(user, copilot_access_info, org)
    copilot_user = Copilot::User.new(user)
    return false if copilot_user.has_free_access? || copilot_user.can_signup_for_free?

    return false if current_repository.in_organization? && current_repository.public?

    true
  end

  sig { params(view: CodeView, org: T.nilable(Organization)).void }
  def instrument_popover_viewed(view, org = nil)
    ref_cta_text = "code_55_percent_faster_with_github_copilot"

    if current_repository.in_organization? && org&.member?(current_user) && !org.adminable_by?(current_user)
      ref_cta_text = "your_organization_can_pay_for_github_copilot"
    end

    GlobalInstrumenter.instrument("analytics.event",
      category: "copilot_popover_code_view",
      action: "copilot_popover_code_view_#{view.serialize}_viewed",
      label:
        "user:#{current_user.id};" +
        "owner:#{current_repository.owner_display_login};" +
        "repo:#{current_repository.id};" +
        "relationship:#{get_user_repo_relationship(org)};" +
        "ref_cta:#{ref_cta_text}"
    )
  end

  sig { params(user: User, org: T.nilable(Organization)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def code_view_popover_payload(user, org = nil)
    if org.nil? || !org.member?(user)
      {
        dismissed: user.dismissed_notice?(UserNotice::CODE_VIEW_COPILOT_POPOVER_NOTICE),
        dismissPath: dismiss_notice_path(UserNotice::CODE_VIEW_COPILOT_POPOVER_NOTICE),
      }
    else
      organization_notice = User::NoticesDependency::ORGANIZATION_NOTICES[:code_view_org_copilot_popover]

      {
        dismissed: user.dismissed_organization_notice?(organization_notice, org),
        dismissPath: dismiss_org_notice_path(org, input: { organizationId: org.id, notice: organization_notice }),
      }
    end
  end

  sig { params(user: User, org: T.nilable(Organization)).returns(T::Boolean) }
  def user_dismissed_popover?(user, org = nil)
    if org.nil? || !org.member?(user)
      user.dismissed_notice?(UserNotice::CODE_VIEW_COPILOT_POPOVER_NOTICE)
    else
      user.dismissed_organization_notice?("code_view_org_copilot_popover", org)
    end
  end

  sig { params(user: User, copilot_access_info: T::Hash[Symbol, T.untyped], org: T.nilable(Organization)).returns(T::Boolean) }
  def copilot_already_provided?(user, copilot_access_info, org = nil)
    if current_repository.in_organization? && !org.nil? && org.member?(user)
      return true unless eligible_for_upsell?(feature: MemberFeatureRequest::Feature::CopilotForBusiness, requester: user, request_entity: org)
      return true if !org.adminable_by?(user) && Copilot::User.new(user).has_cfb_access?
    else
      user_cfb_seat = !copilot_access_info[:business].nil?
      user_has_any_copilot_access = user_cfb_seat || copilot_access_info[:userHasCFIAccess]

      return true if user_has_any_copilot_access
    end

    false
  end

  sig { params(org: T.nilable(Organization)).returns(String) }
  def get_user_repo_relationship(org)
    if !current_repository.in_organization? && current_repository.owner_display_login == current_user.display_login
      "owner"
    elsif org&.adminable_by?(current_user)
      "admin"
    elsif org&.member?(current_user)
      "member"
    else
      "personal"
    end
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  memoize def copilot_business
    business = nil
    org = current_copilot_user_v2&.copilot_organizations&.first

    if org
      business = {
        activeTrial: org.business_trial&.active?,
        trailEndsAt: org.business_trial&.ends_at,
        name: org.organization_object.name,
        path: user_path(org),
        documentation: Copilot::COPILOT_DOCUMENTATION
      }
    end

    business
  end

  sig { returns(String) }
  memoize def get_copilot_docs_url
    if current_user&.organizations.any?
      Copilot::COPILOT_FOR_BUSINESS_DOCUMENTATION
    else
      Copilot::COPILOT_FOR_INDIVIDUALS_DOCUMENTATION
    end
  end
end
