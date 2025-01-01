# typed: true
# frozen_string_literal: true

module Hook::Instrumented
  extend ActiveSupport::Concern
  include Instrumentation::Model
  extend T::Helpers
  requires_ancestor { Hook }

  included do
    T.bind(self, T.class_of(Hook))
    after_commit :instrument_create, on: :create
    after_update :instrument_events_changed, if: :saved_change_to_events?
    after_update :instrument_config_changed, if: :saved_change_to_config_attributes?
    after_update :instrument_active_changed, if: :saved_change_to_active?
    after_destroy :instrument_destroy
  end

  private

  def event_prefix
    :hook
  end

  # Instrumentation payload mixed into every call
  def event_payload
    {
      hook: self,
      hook_type: hook_type,
      name: display_name,
      webhook: webhook?,
      config: masked_config,
      events: events,
      active: active?
    }.merge(installation_target_event_payload)
  end

  def instrument_create
    instrument :create,
      creator: creator_name,
      oauth_application_id: oauth_application.try(:id),
      oauth_application: oauth_application.try(:name)
  end

  def instrument_destroy
    instrument :destroy
  end

  def instrument_events_changed
    instrument :events_changed,
      events_were: events_before_last_save
  end

  def instrument_config_changed
    instrument :config_changed,
      config_was: masked_config(config_attributes_before_last_save)
  end

  def instrument_active_changed
    instrument :active_changed,
      active_was: active_before_last_save,
      staff_disable_reason: stafftools_disable_reason
  end

  def installation_target_event_payload
    Hash.new.tap do |payload|
      case
      when business_hook?
        payload[:business] = installation_target
      when org_hook?
        payload[:org] = installation_target
      when repo_hook?
        repo = installation_target
        payload[:repo] = repo
        payload[:org] = repo.organization if repo.in_organization?
        payload[:user] = repo.user if repo.owner&.user?
        payload[:public_repo] = repo.public?
      when sponsors_listing_hook?
        listing = installation_target
        payload[:sponsors_listing] = listing
        payload[:org] = listing.sponsorable if listing.for_organization?
        payload[:user] = listing.sponsorable if listing.for_user?
      when integration_hook?
        integration = installation_target
        payload[:integration] = integration
        payload[:user] = integration.owner if integration.user_owned?
        payload[:org] = integration.owner if integration.organization_owned?
      end
    end
  end
end
