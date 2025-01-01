# typed: true
# frozen_string_literal: true

module Apps
  class InstallationInstrumenter
    class Actions

      def self.create_event_details(installation, configurations)
        default_payload = installation.event_payload.merge({
          actor: configurations[:audit_log_installer]
        })
        payloads = configurations[:repositories].map do |repo|
          repo_payload = { repo: repo }

          if (owner = repo.owner)
            repo_payload[owner.event_prefix] = owner
          end

          default_payload.merge(repo_payload)
        end

        {
          event_key: "repo.actions_enabled",
          event_payloads: payloads
        }
      end

      def self.repositories_added_event_details(installation, configurations)
        default_payload = {
          actor: configurations[:actor],
          actor_id: configurations[:actor].try(:id)
        }

        repository_ids = configurations[:repository_ids]
        payloads = Repositories::Public.load_repositories(repository_ids).includes(:owner).map do |repo|
          repo_payload = { repo: repo }

          if (owner = repo.owner)
            repo_payload[owner.event_prefix] = owner
          end

          default_payload.merge(repo_payload)
        end

        {
          event_key: "repo.actions_enabled",
          event_payloads: payloads
        }
      end

    end
  end
end
