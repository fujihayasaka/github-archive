# typed: true
# frozen_string_literal: true

module Apps
  class InstallationInstrumenter
    class Codespaces

      def self.create_event_details(installation, configurations)
        default_payload = {
          actor: configurations[:audit_log_installer].display_login,
          actor_id: configurations[:audit_log_installer].id,
        }

        payloads =
          if configurations[:installing_on_all]

            event_prefix = installation.target.event_prefix
            default_payload[event_prefix] = installation.target

            [default_payload]
          elsif configurations[:installing_on_select]
            event_prefix = "repo"

            payloads = configurations[:repositories].map do |repo|
              repo_payload = { repo: repo }

              if (owner = repo.owner)
                repo_payload[owner.event_prefix] = owner
              end

              default_payload.merge(repo_payload)
            end
          else # installing on no repositories, don't instrument
            return {}
          end

        {
          event_key: "#{event_prefix}.codespaces_trusted_repo_access_granted",
          event_payloads: payloads
        }
      end

      def self.delete_event_details(installation)
        prefix = installation.target.event_prefix
        default_payload = { installation.target.event_prefix => installation.target }

        {
          event_key: "#{prefix}.codespaces_trusted_repo_access_revoked",
          event_payloads: [default_payload]
        }
      end

      def self.repositories_added_event_details(installation, configurations)
        default_payload = {
          actor: configurations[:actor].try(:display_login),
          actor_id: configurations[:actor].try(:id)
        }
        repository_ids = configurations[:repository_ids]
        repositories = Repositories::Public.load_repositories(repository_ids).includes(:owner)

        if configurations[:repository_selection] == "all"
          event_prefix = installation.target.event_prefix
          payload = default_payload.merge({
            installation.target.event_prefix => installation.target,
            "repo" => repositories.first
          })

          {
            event_key: "#{event_prefix}.codespaces_trusted_repo_access_granted",
            event_payloads: [payload]
          }
        else
          payloads = repositories.map do |repo|
            repo_payload = { repo: repo }

            if (owner = repo.owner)
              repo_payload[owner.event_prefix] = owner
            end

            default_payload.merge(repo_payload)
          end

          {
            event_key: "repo.codespaces_trusted_repo_access_granted",
            event_payloads: payloads
          }
        end
      end

      def self.repositories_removed_event_details(installation, configurations)
        return unless configurations[:repository_selection] == "selected"

        default_payload = { actor: configurations[:actor].display_login, actor_id: configurations[:actor].id }

        repository_ids = configurations[:repository_ids]
        payloads = Repository.includes(:owner).where(id: repository_ids).map do |repo|
          repo_payload = { repo: repo }

          if (owner = repo.owner)
            repo_payload[owner.event_prefix] = owner
          end

          default_payload.merge(repo_payload)
        end

        {
          event_key: "repo.codespaces_trusted_repo_access_revoked",
          event_payloads: payloads
        }
      end
    end
  end
end
