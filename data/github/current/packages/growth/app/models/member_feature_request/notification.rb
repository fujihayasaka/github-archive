# typed: strict
# frozen_string_literal: true

# This class represents notifications via Notifyd that are sent to
# organization admins or enterprise owners
class MemberFeatureRequest::Notification < ApplicationRecord::Domain::Users
  include ::Permissions::Attributes::Wrapper
  include MemberFeatureRequest::NewsiesAdapter
  self.permissions_wrapper_class = ::Permissions::Attributes::MemberFeatureRequest

  belongs_to :user, optional: false
  belongs_to :entity, polymorphic: true, optional: false

  validates :feature_request_count, presence: true, numericality: { greater_than: 0 }
  validates :user, presence: true
  validates :entity, presence: true

  enum :feature, MemberFeatureRequest::Feature.values.map(&:to_s)

  sig { returns(T::Array[Authzd::Proto::Attribute]) }
  def authzd_attributes
    permissions_wrapper.serialized_subject_attributes
  end

  sig { returns(String) }
  def notification_id
    "member_feature_request_notification_#{feature}_#{id}"
  end

  sig { returns(String) }
  def platform_type_name
    "MemberFeatureRequestNotification"
  end

  sig { returns(String) }
  def message_id
    "<#{entity.name}/feature_requests/#{feature}@#{GitHub.urls.host_name}>"
  end

  sig { params(user: User, unsubscription: T::Hash[Integer, T::Array[MemberFeatureRequest::Feature]]).void }
  def self.unsubscribe(user:, unsubscription:)
    unsubscription.each do |organization_id, features|
      settings = Notifications::Settings::MemberFeatureRequestsSettings.new(
        features: MemberFeatureRequest::Feature.values - features,
      )
      Notifications::Settings.set_member_feature_requests(user, organization_id, settings)
    end
  end
end
