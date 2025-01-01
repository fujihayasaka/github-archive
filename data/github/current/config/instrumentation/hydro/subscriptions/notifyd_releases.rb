# typed: true
# frozen_string_literal: true

require "notifyd-client"

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("release.first_published") do |payload|
    next unless payload[:release] && payload[:actor]
    next unless FeatureFlag.vexi.enabled_or_raise?(:notifyd_releases_hydro_publisher, payload[:release].repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    Notifyd::NotifyPublisher.new.async_publish(
      actor_id: payload[:actor].id,
      subject_id: payload[:release].id,
      subject_klass: payload[:release].class.name,
      context: {
        actor_id: payload[:actor].id,
        actor_login: payload[:actor].display_login,
        operation: "create"
      }
    )
  end
end
