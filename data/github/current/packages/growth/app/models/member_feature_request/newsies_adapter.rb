# typed: strict
# frozen_string_literal: true

# This module implements methods expected by Newsies.
module MemberFeatureRequest::NewsiesAdapter
  # NOTE: The including class must define entity and async_entity. MemberFeatureRequest::Notification
  #  does this through a relation
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
    async_title.sync
  end

  sig { returns(Promise[String]) }
  def async_title
    async_requesters.then { |requesters| "New requests from #{requesters}" }
  end

  sig { returns(String) }
  def body
    async_body.sync
  end

  sig { returns(Promise[String]) }
  def async_body
    Promise.all([async_safe_profile_name, async_requesters]).then do |safe_profile_name, requesters|
      "[#{safe_profile_name}] You have #{feature_request_count} " +
        "new #{"request".pluralize(feature_request_count)} from #{requesters} for #{feature_request&.formatted_text}"
    end
  end

  sig { returns(Promise[String]) }
  def async_safe_profile_name
    async_entity.then do |entity|
      case entity
      when Business
        entity.safe_profile_name
      when Organization
        entity.async_profile.then do
          entity.safe_profile_name
        end
      end
    end
  end

  sig { returns(String) }
  def permalink
    async_permalink.sync
  end

  sig { returns(Promise[String]) }
  def async_permalink
    async_entity.then do |entity|
      case entity
      when Business
        "#{GitHub.url}/enterprises/#{entity.display_login}/settings/copilot"
      when Organization
        async_user.then do |user|
          if copilot_for_business? && Copilot::Organization.new(entity).can_enable_org_to_assign_seats?(user)
            "#{GitHub.url}/organizations/#{entity.display_login}/settings/copilot/seat_management"
          else
            "#{GitHub.url}/organizations/#{entity.display_login}/settings/member_feature_requests"
          end
        end
      end
    end
  end

  sig { params(viewer: User).returns(Promise[T::Boolean]) }
  def async_readable_by?(viewer)
    return Promise.new.fulfill(false) unless viewer.id == self.user_id

    # The viewer must be a business / organization admin
    async_entity.then { |entity| entity.async_adminable_by?(viewer) }
  end

  sig { params(viewer: User).returns(T::Boolean) }
  def readable_by?(viewer)
    async_readable_by?(viewer).sync
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

  sig { returns(String) }
  memoize def requesters
    async_requesters.sync
  end

  sig { returns(Promise[String]) }
  memoize def async_requesters
    async_entity.then do |entity|
      case entity
      when Business
        "admins"
      when Organization
        "members"
      end
    end
  end
end
