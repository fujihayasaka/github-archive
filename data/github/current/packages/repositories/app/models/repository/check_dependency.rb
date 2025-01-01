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
      value = GitHub.kv.get(auto_trigger_key(app_id)).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
      value != "false"
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
    GitHub.kv.set(auto_trigger_key(app.id), value.to_s) # rubocop:todo GitHub/DoNotUseGlobalKv

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
    preferences = { auto_trigger_checks: [] }

    installations_with_access = IntegrationInstallation.with_resources_on(subject: self, resources: "checks", min_action: :write)
    installations_with_access.each_with_object(preferences[:auto_trigger_checks]) do |installation, memo|
      app = Integration.find(installation.integration_id)

      memo << {
        app: app,
        setting: auto_trigger_checks_for?(app_id: app.id),
      }
    end

    preferences
  end

  private

  def auto_trigger_key(app_id)
    "checks.auto_trigger_checks.#{id}.#{app_id}"
  end
end
