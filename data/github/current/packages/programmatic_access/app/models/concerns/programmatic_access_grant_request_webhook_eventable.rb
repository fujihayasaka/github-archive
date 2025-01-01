# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrantRequestWebhookEventable
  extend ActiveSupport::Concern

  # Public: Pre-generate a webhook payload for a PAT request. This is useful for actions that
  # destroy the PAT request before a worker can be scheduled to build and send the webhook payload.
  #
  # action            - The action that triggered this event. (ex: :created, :approved, :denied and :cancelled).
  # actor             - The actor that triggered this event. (ex: User, Bot, etc.)
  # token_expires_at  - The associated token expiration date and time. In most cases we can get this value
  #                     from Authnd. However, in cases such as creating a brand new token, we create the PAT
  #                     request before creating a token with Authnd, so we need to pass this value in.
  #
  # Returns nothing.
  def generate_webhook_payload(action:, current_actor:, token_expires_at: nil)
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    event = Hook::Event::PersonalAccessTokenRequestEvent.new(
      action: action,
      actor_id: current_actor.id,
      target_id: self.target&.id,
      target_type: self.target.class.name,
      user_programmatic_access_id: self.user_programmatic_access_id,
      token_expires_at: token_expires_at&.utc&.iso8601,
      triggered_at: Time.now,
      permissions_added: self.permissions_difference[:permissions_added],
      permissions_unchanged: self.permissions_difference[:permissions_unchanged],
      permissions_upgraded: self.permissions_difference[:permissions_upgraded]
    )

    # Only include repository IDs if the request selected a subset of repositories to prevent us
    # potentially building a payload that is too large if a user selected all repositories.
    if repository_selection == ProgrammaticAccessGrant::RepositorySelection::SUBSET.to_s
      event.repositories = self.repositories&.pluck(:id)
    end

    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  # Public: Queue a webhook delivery job for a PAT request event.
  #
  # Returns nothing.
  def queue_webhook_delivery
    return unless defined?(@delivery_system)
    @delivery_system.deliver_later
  end
end
