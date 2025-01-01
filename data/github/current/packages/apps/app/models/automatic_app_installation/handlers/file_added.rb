# typed: strict
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    class FileAdded < BaseHandler
      include Scientist
      extend Scientist

      alias push originator

      ALLOWED_PATHS = T.let([".github"], T::Array[String])

      sig { returns(T.untyped) }
      def originator; super; end

      sig { returns(T::Array[IntegrationInstallTrigger]) }
      def install_integration
        this_push = T.cast(push, Repositories::RefUpdate)

        self.class.matched_install_triggers(install_triggers.to_a, this_push).each do |install_trigger|
          target_id = T.must(this_push.repository.owner).id
          integration_id = T.must(install_trigger.integration).id

          options = {
            enqueued_timestamp: Time.now.to_i,
            entry_point: :automatic_app_installation_handler_file_added,
            pusher: this_push.pusher,
            before: this_push.before,
            after: this_push.after,
            ref: this_push.ref
          }

          InstallAutomaticIntegrationsJob.perform_later(
            target_id,
            integration_id,
            install_trigger.id,
            Array(this_push.repository.id),
            options
          )
        end
      end

      sig { params(integration: Integration, installation: IntegrationInstallation, target: User, installer: User, repositories: T.untyped, options: T::Hash[T.any(Symbol, String), T.any(String, User, Integer)]).returns(T.nilable(T::Array[Repository])) }
      def self.after_integration_installed(integration:, installation:, target:, installer:, repositories:, options: {})
        before = options[:before] || options["before"]
        after = options[:after] || options["after"]
        ref = options[:ref] || options["ref"]
        pusher = options[:pusher] || options["pusher"]

        valid_options = before.present? && after.present? && ref.present? && pusher.present?
        return unless valid_options

        repositories.each do |repo|
          payload = {
            # only deliver event for the newly installed integration
            target_hook: integration.hook,
            repo: repo,
            pusher: pusher,
            ref: ref,
            before: before,
            after: after,
            triggered_at: Time.now,
          }

          event = Hook::Event::PushEvent.new(payload)
          delivery_system = Hook::DeliverySystem.new(event)

          delivery_system.generate_push_event_hookshot_payloads
          delivery_system.deliver_push_event_later
        end
      end

      sig { params(install_trigger: IntegrationInstallTrigger, push: Repositories::RefUpdate).returns(T::Boolean) }
      def self.can_auto_install?(install_trigger, push)
        Apps::Privileged.can_auto_install?(self, install_trigger.integration, repo: push.repository)
      end

      sig { returns(T::Array[String]) }
      def self.allowed_file_added_regex_prefixes
        (
          ALLOWED_PATHS.map { |p| "\\A#{Regexp.escape(p)}/" } +
          ALLOWED_PATHS.map { |p| "\\A#{Regexp.escape(p)}\\/" }
        ).map { |p| [p, "(?-mix:#{p}"] }.flatten
      end

      sig { params(install_trigger: IntegrationInstallTrigger).returns(T::Boolean) }
      def self.validate_trigger(install_trigger)
        file_added_trigger_path = install_trigger.path
        return true if install_trigger.deactivated && file_added_trigger_path.nil?
        return true if !file_added_trigger_path.nil? &&
                  allowed_file_added_regex_prefixes.any? { |p| file_added_trigger_path.starts_with?(p) }

        install_trigger.errors.add(:path, "must start with one of #{allowed_file_added_regex_prefixes.join(", ")} for file_added triggers")
        false
      end

      sig { params(install_triggers: T::Array[IntegrationInstallTrigger], push: T.nilable(Repositories::RefUpdate)).returns(T::Array[IntegrationInstallTrigger]) }
      def self.matched_install_triggers(install_triggers, push)
        return [] if install_triggers.none?
        return [] unless push

        # Filter all trigger's that aren't eligible for automatic installation
        install_triggers = install_triggers.select do |install_trigger|
          can_auto_install?(install_trigger, push)
        end

        return [] if install_triggers.none?

        if install_triggers.all? { |t| validate_trigger(t) }
          pushed_file_paths = pushed_file_paths(push, [".github"])
        else
          pushed_file_paths = pushed_file_paths(push, [])
        end

        return [] if pushed_file_paths.none?

        matched_triggers = install_triggers.select do |install_trigger|
          path_regex = Regexp.compile(Regexp.new(install_trigger.path))
          pushed_file_paths.any? { |other| path_regex.match?(other) }
        end

        matched_triggers
      end

      sig { params(push: Repositories::RefUpdate, paths: T::Array[T.nilable(String)]).returns(T::Array[String]) }
      def self.pushed_file_paths(push, paths)
        changed_files = push.changed_files(decompose_renames: true, paths: paths)
        return [] if changed_files.nil?

        if push.initial_commit?
          # force the Push model to reload commits (prevents stale commits list)
          push.commits = nil
          commits = push.commits_pushed

          # Pushes on enterprise can be very large and take many hours to iterate over all diffs, consuming
          # memory in the process. To protect against that, if the push is too large, only process most recent
          # Pushes::CommitsHelper::LARGE_PUSH_THRESHOLD (2048) commits
          commits = commits.last(Pushes::CommitsHelper::LARGE_PUSH_THRESHOLD) if GitHub.enterprise?

          commits.flat_map do |c|
            c.diff.map(&:path)
          end.uniq
        else
          return [] if changed_files.nil?

          changed_files.map do |file|
            file.addition? ? file.path : nil
          end.compact
        end
      end
    end
  end
end
