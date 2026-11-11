# typed: true
# frozen_string_literal: true

require "notifyd-client"

# Hydro subscriber that, behind the
# `notifyd_repository_advisories_stateful_mentions` vexi flag, invokes the
# Notifyd::RepositoryAdvisoryAdapter to compute stateful mention recipients on
# repository_advisory.create and repository_advisory.update events.
#
# This is a shadow experiment for github/notifyd#5695: we run the compute
# purely so we can measure the per-event cost via dogstats. The result is
# intentionally discarded -- newsies still owns delivery.
#
# Event names: these subscribe to the GlobalInstrumenter events emitted from
# Repos::AdvisoriesController (`repository_advisory.create` on POST and
# `repository_advisory.update` on PATCH). The similarly named model-level
# `instrument :open` / `instrument :update` callbacks on RepositoryAdvisory
# go through a different instrumenter and are NOT what we are subscribing to
# here.
#
# Mentions are sourced from the `description` attribute (the user-facing
# field on modern advisories), NOT the `body` attribute that
# RepositoryAdvisory#mentioned_user_ids currently parses via
# GitHub::UserContent. The legacy `body` attribute is deprecated for new
# advisories (see Repos::AdvisoriesController#update_body and #advisory_params,
# which only permit :description). The existing newsies path therefore
# detects no mentions on modern advisories. By parsing `description` here we
# measure the latency of computing mentions on the field users actually
# write into, which is the relevant cost for the future stateful-mentions
# path. The output will not match newsies output for legacy `body`-bearing
# advisories -- that parity reconciliation is tracked separately as a
# blocker in github/notifyd#5632.
#
# For updates, the controller's GlobalInstrumenter payload does not include
# the previous/current description, so we derive them from the advisory's
# `previous_changes["description"]`, which is still populated on the
# just-saved record at the time this synchronous subscriber runs.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("repository_advisory.create") do |payload|
    advisory = payload[:repository_advisory]
    next unless advisory
    next unless advisory.repository&.owner.present?
    next unless FeatureFlag.vexi.enabled?(
      :notifyd_repository_advisories_stateful_mentions,
      advisory.repository,
      default: false,
    )

    Notifyd::RepositoryAdvisoryAdapter.new(advisory, {
      operation: "create",
      current_body: advisory.description,
    }).explicit_recipients
  rescue => e
    Notifyd::NotifydFailbot.report(e,
      repository_advisory_id: advisory&.id,
      operation: "create",
    )
  end

  subscribe("repository_advisory.update") do |payload|
    advisory = payload[:repository_advisory]
    next unless advisory
    next unless advisory.repository&.owner.present?

    description_change = advisory.previous_changes["description"]
    next unless description_change

    next unless FeatureFlag.vexi.enabled?(
      :notifyd_repository_advisories_stateful_mentions,
      advisory.repository,
      default: false,
    )

    previous_body, current_body = description_change
    Notifyd::RepositoryAdvisoryAdapter.new(advisory, {
      operation: "update",
      current_body: current_body,
      previous_body: previous_body,
    }).explicit_recipients
  rescue => e
    Notifyd::NotifydFailbot.report(e,
      repository_advisory_id: advisory&.id,
      operation: "update",
    )
  end
end
