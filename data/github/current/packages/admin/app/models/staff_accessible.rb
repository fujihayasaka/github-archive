# typed: true
# frozen_string_literal: true

# Mixin for assets that can be accessed by staff with user permission
module StaffAccessible
  extend ActiveSupport::Concern
  include Kernel

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))

    has_many :staff_access_requests, as: :accessible
    has_many :staff_access_grants, as: :accessible
  end

  def active_staff_access_grant
    grant = latest_staff_access_grant
    grant if grant&.active?
  end

  def active_staff_access_request
    request = latest_staff_access_request
    request if request&.active?
  end

  def latest_staff_access_grant
    T.unsafe(self).staff_access_grants.order(created_at: :desc).limit(1).first
  end

  def latest_staff_access_request
    T.unsafe(self).staff_access_requests.order(created_at: :desc).limit(1).first
  end

  def event_prefix
    # models which include this mixin must implement event_prefix
    raise NotImplementedError
  end
end
