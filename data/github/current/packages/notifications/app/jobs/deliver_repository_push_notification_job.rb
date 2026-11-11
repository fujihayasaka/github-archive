# typed: true
# frozen_string_literal: true

# This job replaces the legacy `email` service from `github-services` which,
# when configured, sends email notifications about Push events to repositories.
#
# See https://github.com/github/experience-product/issues/114 for more detail
class DeliverRepositoryPushNotificationJob < ApplicationJob
  queue_as :deliver_repository_push_notifications

  retry_on_dirty_exit

  def perform(payload)
    @payload = payload
    return unless should_deliver?

    hash = {
      repository: repository,
      ref: @payload[:ref],
      before: @payload[:before],
      after: @payload[:after],
      pusher: pusher,
      address: hook_configuration["address"],
      secret: hook_configuration["secret"]
    }

    RepositoryPushNotificationMailer.build(**hash).deliver_later
  end

  private

  def should_deliver?
    return false if pusher&.spammy?
    return false if repository&.spammy?
    return false if repository.nil?
    return false unless hook_configuration.present?
    return false unless hook_configuration["address"].present?
    true
  end

  def hook_configuration
    return @hook_configuration if defined?(@hook_configuration)
    @hook_configuration = Hook.active.where(
      installation_target: repository,
      name: "email",
    ).first&.config_attributes
  end

  def repository
    @repository ||= Repositories.domain.by_id(@payload[:repository_id])
  end

  def pusher
    return @pusher if defined?(@pusher)
    @pusher = User.find_by(id: @payload[:pusher_id]) if @payload[:pusher_id]
  end
end
