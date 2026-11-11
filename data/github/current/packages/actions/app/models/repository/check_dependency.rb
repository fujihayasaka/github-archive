# typed: true
# frozen_string_literal: true

module Repository::CheckDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  include GitHub::ResilienceMixin

  requires_ancestor { Repository }

  # CheckAnnotations for the given sha
  #
  # sha - String commit oid
  # limit - Integer maximum number of annotations to return
  # filenames (optional) - Array of String file paths
  # inline_only (optional) - Boolean whether to only return "inline annotations", e.g. annotations
  #                          associated with an individual file via valid start and end line
  #
  # Returns an ActiveRecord::Relation
  def annotations_for(sha:, filenames: [], limit:, inline_only: false)
    latest_run_ids = CheckRun.latest_ids_with_annotations_for_sha_and_repository_with_limit(sha, self, CheckRun.default_max_check_suites_per_sha_limit)

    return CheckAnnotation.none if latest_run_ids.empty?

    args = {
      repository_id: self.id,
      check_run_id: latest_run_ids
    }
    args[:filename] = filenames if filenames.any?
    args[:end_line] = (1..) if inline_only # => Equivalent to `where("end_line >= 1")`

    CheckAnnotation.where(args).limit(limit)
  end

  # Does this repository have applications that will produce code checks on it?
  #
  # Returns boolean.
  def has_apps_that_write_checks?
    return @installations_with_access.any? if defined?(@installations_with_access)

    @installations_with_access ||= IntegrationInstallation.with_resources_on(
      subject: self,
      resources: "checks",
      min_action: :write,
    )

    @installations_with_access.any?
  end

  # Is this repository configured to create check suites automatically
  # for the given app? Defaults to true.
  #
  # app_id: - The id of a GitHub App.
  #
  # Returns boolean.
  def auto_trigger_checks_for?(app_id:)
    GitHub.tracer.in_span("Repository::CheckDependency.auto_trigger_checks_for?", kind: :internal) do
      github_apps_to_exclude = [GitHub.launch_github_app&.id, GitHub.launch_lab_github_app&.id, GitHub.dependabot_github_app&.id]
      return false if github_apps_to_exclude.include?(app_id)
      value = kv.get(auto_trigger_key(app_id)).value { nil }
      value != "false"
    end
  end

  # Batched form of #auto_trigger_checks_for? that resolves the preference for
  # many apps with a single KV mget instead of one get per app. This avoids an
  # N+1 on actions_key_values when serializing check suite preferences.
  #
  # app_ids: - Array of GitHub App ids.
  #
  # Returns a Hash mapping each app_id to its boolean preference.
  def auto_trigger_checks_for(app_ids:)
    GitHub.tracer.in_span("Repository::CheckDependency.auto_trigger_checks_for", kind: :internal) do
      github_apps_to_exclude = [GitHub.launch_github_app&.id, GitHub.launch_lab_github_app&.id, GitHub.dependabot_github_app&.id]

      keys_by_app_id = {}
      app_ids.each do |app_id|
        next if github_apps_to_exclude.include?(app_id)
        keys_by_app_id[app_id] = auto_trigger_key(app_id)
      end

      values_by_key =
        if keys_by_app_id.empty?
          {}
        else
          keys = keys_by_app_id.values
          keys.zip(kv.mget(keys).value { [] }).to_h
        end

      app_ids.index_with do |app_id|
        next false if github_apps_to_exclude.include?(app_id)
        values_by_key[keys_by_app_id[app_id]] != "false"
      end
    end
  end

  # Control form used by the batching experiment: resolves the preference for
  # each app with an individual KV get (the original, pre-batching behaviour of
  # one query per app). Retained unchanged so the Scientist experiment in
  # #auto_trigger_checks_settings has a faithful control to compare against.
  #
  # app_ids: - Array of GitHub App ids.
  #
  # Returns a Hash mapping each app_id to its boolean preference.
  def auto_trigger_checks_for_each(app_ids:)
    app_ids.index_with { |app_id| auto_trigger_checks_for?(app_id: app_id) }
  end

  # Resolves the auto-trigger-checks preference for many apps, returning a Hash
  # mapping each app_id to its boolean preference.
  #
  # This is the N+1 cutover point on actions_key_values. Replacing the per-app
  # KV gets with a single batched mget changes the query shape (N single-key
  # `IN (...)` lookups become one multi-key lookup), so the batched candidate is
  # proven equivalent to the per-app control by a Scientist experiment while the
  # feature flag is off, and becomes the sole path once
  # `batch_auto_trigger_checks_kv` is enabled.
  #
  # app_ids: - Array of GitHub App ids.
  #
  # Returns a Hash mapping each app_id to its boolean preference.
  def auto_trigger_checks_settings(app_ids:)
    if FeatureFlag.vexi.enabled?(:batch_auto_trigger_checks_kv, default: false)
      auto_trigger_checks_for(app_ids: app_ids)
    else
      science "batch_auto_trigger_checks_kv" do |e|
        e.use { auto_trigger_checks_for_each(app_ids: app_ids) } # control = one KV get per app
        e.try { auto_trigger_checks_for(app_ids: app_ids) }      # candidate = single KV mget

        e.context(repository_id: id, app_count: app_ids.size)
        e.compare { |control, candidate| control == candidate }
        e.clean { |settings| settings.sort.to_h }
      end
    end
  end

  # Set the preference on whether to automatically create check suites
  # for the given app.
  #
  # app:    - The GitHub App.
  # value:  - The string to represent the app's preference: 'true' or 'false'.
  #
  # Returns nothing.
  def set_auto_trigger_checks(actor:, app:, value:)
    kv.set(auto_trigger_key(app.id), value.to_s)

    payload = {
      prefix: :checks,
      app: app,
    }.tap do |p|
      if actor.is_a?(User)
        p[:actor] = actor
      else
        p[actor.event_prefix] = actor if actor
      end
    end

    if value == "true"
      instrument :auto_trigger_enabled, payload
    else
      instrument :auto_trigger_disabled, payload
    end
  end

  # What are application's preferences for check suites on this repo?
  #
  # Examples
  #
  #   check_suite_preferences
  #   # => { :auto_trigger_checks =>
  #            [{ :app => #<Integration id: 2, owner_id: 340, bot_id: 5346, name: "Super-CI"...>,
  #               :setting => true}]}
  #
  # Returns a Hash.
  def check_suite_preferences
    installations_with_access = IntegrationInstallation.with_resources_on(subject: self, resources: "checks", min_action: :write)
    apps = installations_with_access.map { |installation| Integration.find(installation.integration_id) }
    settings = auto_trigger_checks_settings(app_ids: apps.map(&:id))

    auto_trigger_checks = apps.map do |app|
      {
        app: app,
        setting: settings[app.id],
      }
    end

    { auto_trigger_checks: auto_trigger_checks }
  end

  private

  def auto_trigger_key(app_id)
    "checks.auto_trigger_checks.#{id}.#{app_id}"
  end

  def kv
    Actions::KV.for_partition_key(id)
  end
end
