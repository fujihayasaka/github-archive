# typed: strict
# frozen_string_literal: true

# This module implements methods expected by Newsies.
module MemberFeatureRequest::NewsiesAdapter
  include GitHub::Memoizer
  extend T::Helpers

  requires_ancestor { MemberFeatureRequest::Notification }

  sig { returns(T.self_type) }
  def notifications_thread
    self
  end

  sig { returns(T.any(Business, Organization)) }
  def notifications_list
    entity
  end

  sig { returns(String) }
  def title
    "New requests from #{requesters}"
  end

  sig { returns(String) }
  def body
    "[#{entity.safe_profile_name}] You have #{feature_request_count} " +
      "new #{"request".pluralize(feature_request_count)} from #{requesters} for #{feature_request&.formatted_text}"
  end

  sig { returns(String) }
  def permalink
    case entity
    when Business
      "#{GitHub.url}/enterprises/#{entity.display_login}/settings/copilot"
    when Organization
      if copilot_for_business? && Copilot::Organization.new(organization).can_enable_org_to_assign_seats?(user)
        "#{GitHub.url}/organizations/#{organization.display_login}/settings/copilot/seat_management"
      else
        "#{GitHub.url}/organizations/#{organization.display_login}/settings/member_feature_requests"
      end
    end
  end

  sig { params(viewer: User).returns(T::Boolean) }
  def async_readable_by?(viewer)
    viewer.id == self.user_id
  end

  sig { returns(T.any(Business, Organization)) }
  memoize def entity
    return business if entity_type == "Business"

    organization
  end

  private

  sig { returns(T::Boolean) }
  def copilot_for_business?
    feature_request == MemberFeatureRequest::Feature::CopilotForBusiness
  end

  sig { returns(T.nilable(MemberFeatureRequest::Feature)) }
  memoize def feature_request
    MemberFeatureRequest::Feature.from_string(feature)
  end

  sig { returns(Business) }
  memoize def business
    T.must(Platform::Loaders::ActiveRecord.load(Business, self.entity_id).sync)
  end

  sig { returns((Organization)) }
  memoize def organization
    org = Platform::Loaders::ActiveRecord.load(Organization, self.entity_id).sync
    T.must(org).async_profile.sync
    T.must(org)
  end

  sig { returns(String) }
  memoize def requesters
    case entity
    when Business
      "admins"
    when Organization
      "members"
    end
  end
end
