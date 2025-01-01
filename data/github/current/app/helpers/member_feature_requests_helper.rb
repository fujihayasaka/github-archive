# typed: strict
# frozen_string_literal: true

module MemberFeatureRequestsHelper

  include FeatureFlagHelper

  # This method checks if a feature upsell is eligible for the given requester, organization and/or repository.
  #
  # @param feature [MemberFeatureRequest::Feature] the feature that the requester requested
  # @param requester [User] the user who is requesting the feature
  # @param repo [Repository] the repository that the requester is requesting the feature for
  # @param org [Organization] the organization that the requester is requesting the feature for
  #
  # @return [Boolean] feature is displayable or not.
  # @example
  #  eligible_for_upsell?(feature: feature, requester: requester, request_entity: organization or business, repo: repository) => true
  sig do params(feature: MemberFeatureRequest::Feature, requester: T.nilable(User), repo: T.nilable(Repository),
    request_entity: T.nilable(Organization)).returns(T::Boolean)
  end
  def eligible_for_upsell?(feature:, requester: nil, repo: nil, request_entity: nil)
    return false if requester.nil?

    if feature == MemberFeatureRequest::Feature::CopilotForBusiness
      return false if request_entity.nil?

      if !request_entity.adminable_by?(requester)
        return !feature.supported?(repo: repo, request_entity: request_entity) || !MemberFeatureRequest.request_fulfilled?(
          requester,
          request_entity,
          MemberFeatureRequest::Feature::CopilotForBusiness
        )
      end
    end

    T.must((repo.present? || request_entity.present?) && !feature.supported?(repo: repo, request_entity: request_entity))
  end

  sig { params(request_entity: Organization, user: User).returns(T::Boolean) }
  def show_requests_from_members_menu_for_current_organization?(request_entity, user)
    return false if GitHub.enterprise?
    return false unless request_entity.adminable_by?(user) || request_entity.billing_manager?(user)

    latest_member_feature_request_for_organization(request_entity).present?
  end

  sig { params(request_entity: Organization).returns(T.nilable(MemberFeatureRequest)) }
  def latest_member_feature_request_for_organization(request_entity)
    MemberFeatureRequest.latest_member_feature_request(request_entity)
  end

  sig { params(request_entity: Organization).returns(T::Boolean) }
  def has_unread_feature_requests?(request_entity)
    # https://github.com/github/app-partitioning/issues/53
    current_user = T.unsafe(self).current_user
    return false unless current_user

    latest_feature = latest_member_feature_request_for_organization(request_entity)
    return false unless latest_feature

    latest_visit = user_visited_feature_request_page_at(request_entity, current_user)

    latest_visit.nil? || latest_visit.before?(latest_feature.created_at)
  end

  sig { params(request_entity: Organization, user: User).void }
  def user_visited_feature_request_page!(request_entity, user)
    Growth::LastActivity::KV.store.set(org_user_visited_feature_request_page_key(request_entity, user), Time.current.iso8601)
  end

  sig { params(request_entity: Organization, user: User).returns(T.nilable(Time)) }
  def user_visited_feature_request_page_at(request_entity, user)
    value = Growth::LastActivity::KV.store.get(org_user_visited_feature_request_page_key(request_entity, user)).value { nil }
    return if value.nil?

    begin
      Time.zone.iso8601(value)
    rescue ArgumentError
      nil
    end
  end

  sig { params(request_entity: Organization).void }
  def user_seen_copilot_for_business_section!(request_entity)
    current_user = T.unsafe(self).current_user
    return false unless current_user

    ActiveRecord::Base.connected_to(role: :writing) do
      Growth::LastActivity::KV.store.set(org_user_seen_copilot_for_business_section_key(request_entity, current_user), "true")
    end
  end

  sig { params(request_entity: Organization).returns(T::Boolean) }
  def user_seen_copilot_for_business_section?(request_entity)
    # https://github.com/github/app-partitioning/issues/53
    current_user = T.unsafe(self).current_user
    return false unless current_user

    ActiveRecord::Base.connected_to(role: :reading) do
      Growth::LastActivity::KV.store.get(org_user_seen_copilot_for_business_section_key(request_entity, current_user)).value { nil } == "true"
    end
  end

  sig { params(feature: MemberFeatureRequest::Feature, user: T.nilable(User), org: T.nilable(Organization), repo: T.nilable(Repository)).returns(T.nilable(Copilot::Types::FeatureRequestInfo)) }
  def feature_request_info_payload(feature, user = nil, org = nil, repo = nil)
    return nil unless org && user

    billing_entity = org.delegate_billing_to_business? && org.adminable_by?(user) ? org.business : org
    member_feature_request = MemberFeatureRequest.find_request(user, org, feature, billing_entity)

    {
      showFeatureRequest: show_feature_request?(feature, user, org, repo, member_feature_request),
      alreadyRequested: member_feature_request&.requested? || false,
      dismissed: member_feature_request&.dismissed? || false,
      featureName: feature.to_s,
      requestPath: Rails.application.routes.url_helpers.org_member_feature_requests_path(org: org.display_login),
      isEnterpriseRequest: org.delegate_billing_to_business? && org.adminable_by?(user),
      dismissedAt: member_feature_request&.dismissed_at&.strftime("%b %-d, %Y"),
      billingEntityId: org.business&.id.to_s,
      latestUsernameRequests: MemberFeatureRequest.latest_members_by_feature_request(org, feature, 1),
      amountOfUserRequests: MemberFeatureRequest.total_for_feature(org, feature),
    }
  end

  private

  sig { params(feature: MemberFeatureRequest::Feature, user: User, request_entity: Organization, repo: T.nilable(Repository), member_feature_request: T.nilable(MemberFeatureRequest)).returns(T::Boolean) }
  def show_feature_request?(feature, user, request_entity, repo, member_feature_request)
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false if user.is_enterprise_managed?
    return false if member_feature_request.present? && member_feature_request.fulfilled?

    if request_entity.adminable_by?(user)
      return false unless request_entity.delegate_billing_to_business?
      return false unless business = request_entity.business
      return false if business.owner?(user)

      if feature == MemberFeatureRequest::Feature::CopilotForBusiness
        return false if Copilot::Organization.new(request_entity).copilot_enabled?
      end

      return true
    end

    eligible_for_upsell?(feature:, requester: user, request_entity:, repo:)
  end

  sig { params(request_entity: Organization, user: User).returns(String) }
  def org_user_visited_feature_request_page_key(request_entity, user)
    "user_visited_feature_request_page_#{request_entity.id}.#{user.id}"
  end

  sig { params(request_entity: Organization, user: User).returns(String) }
  def org_user_seen_copilot_for_business_section_key(request_entity, user)
    "user_seen_copilot_for_business_section.#{request_entity.id}.#{user.id}"
  end
end
