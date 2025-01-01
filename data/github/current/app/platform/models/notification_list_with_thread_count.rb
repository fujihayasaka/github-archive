# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationListWithThreadCount
  attr_reader :count, :unread_count, :user

  def initialize(list:, count:, unread_count:, user:)
    @list = list
    @count = count
    @unread_count = unread_count
    @user = user
  end

  def readable_by?(viewer)
    async_readable_by?(viewer).sync
  end

  def async_target_for_conditional_access
    async_list.then do |list|
      next list.async_repository.then(&:async_target_for_conditional_access) if list.respond_to?(:async_repository)
      next list.async_target_for_conditional_access if list.respond_to?(:async_target_for_conditional_access)
      raise Platform::Errors::InternalExecution, "async_target_for_conditional_access undefined for #{list.class.name}"
    end
  end

  def async_readable_by?(viewer, unauthorized_account_ids: [])
    return Promise.resolve(false) unless user.id == viewer.id

    async_list.then do |list|
      next false unless list.present?

      Promise.all([
        async_in_unauthorized_account?(list, unauthorized_account_ids),
        list.async_readable_by?(viewer),
      ]).then do |(in_unauthorized_account, readable)|
        next false if in_unauthorized_account
        readable
      end
    end
  end

  def async_list
    Platform::Loaders::ActiveRecord.load(@list.class, @list.id, security_violation_behaviour: :nil)
  end

  private

  def async_in_unauthorized_account?(list, unauthorized_account_ids)
    return Promise.resolve(false) unless unauthorized_account_ids.present?

    (list.try(:async_owner) || list.try(:async_organization)).then do |owner|
      next false unless owner.present?
      unauthorized_account_ids.include?(owner.id)
    end
  end
end
