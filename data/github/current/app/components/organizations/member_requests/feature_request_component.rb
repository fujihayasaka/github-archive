# typed: true
# frozen_string_literal: true

class Organizations::MemberRequests::FeatureRequestComponent < ApplicationComponent

  include ApplicationComponent::Rescuable

  rescue_from StandardError, with: :nothing

  renders_one :request_message
  renders_one :request_cta, lambda { |**system_arguments|
    system_arguments[:tag] = :button
    system_arguments[:data] = {
      action: "click:feature-request#submit",
      target: "feature-request.requestButton",
    }.merge(system_arguments[:data] || {})
    Primer::Beta::Button.new(**system_arguments)
  }

  renders_one :requested_message
  renders_one :remove_request_cta, lambda { |**system_arguments|
    system_arguments[:tag] = :button
    system_arguments[:display] = system_arguments[:display] || :inline
    system_arguments[:color] = system_arguments[:color] || :danger
    system_arguments[:data] = {
      action: "click:feature-request#cancel",
      target: "feature-request.cancelButton",
    }.merge(system_arguments[:data] || {})
    Primer::Beta::Button.new(**system_arguments)
  }

  sig { returns T.nilable(Organization) }
  attr_reader :organization

  sig { returns T.nilable(MemberFeatureRequest::Feature) }
  attr_reader :feature

  sig { returns T.nilable(User) }
  attr_reader :requester

  sig { returns T.nilable(String) }
  attr_reader :learn_more_url

  sig { returns T.untyped }
  attr_reader :system_arguments

  sig do params(
    requester: T.nilable(User),
    feature: T.nilable(MemberFeatureRequest::Feature),
    organization: T.nilable(Organization),
    learn_more_url: T.nilable(String),
    system_arguments: Primer::SystemArgumentsValue,
  ).void
  end
  def initialize(requester:, feature:, organization:, learn_more_url: nil, **system_arguments)
    @organization = organization
    @requester = requester
    @feature = feature
    @learn_more_url = learn_more_url
    @system_arguments = system_arguments
  end

  sig { returns T::Boolean }
  def render?
    return false if GitHub.enterprise?
    return false unless organization.present?
    return false unless requester.present?
    return false if requester_can_enable_feature_in_enterprise?
    return true unless organization&.adminable_by?(requester)
    return true if organization&.delegate_billing_to_business?

    false
  end

  memoize def requested?
    member_feature_request&.requested?
  end

  memoize def dismissed?
    member_feature_request&.dismissed?
  end

  memoize def dismissed_at
    member_feature_request&.dismissed_at&.strftime("%b %-d, %Y")
  end

  memoize def requested_for_enterprise?
    organization&.adminable_by?(requester) && member_feature_request&.requested?
  end

  memoize def requested_for_organization?
    member_feature_request&.requested? && !organization&.adminable_by?(requester)
  end

  private

  sig { returns T::Boolean }
  def requester_can_enable_feature_in_enterprise?
    return false unless organization&.delegate_billing_to_business?

    T.must(organization&.business&.adminable_by?(requester))
  end

  sig { returns T.nilable(MemberFeatureRequest) }
  memoize def member_feature_request
    billing_entity = T.must(organization).adminable_by?(requester) ? T.must(organization).business : T.must(organization)
    MemberFeatureRequest.find_request(T.must(requester), T.must(organization), T.must(feature), billing_entity)
  end
end
