# typed: false
# frozen_string_literal: true

module PackageRegistry
  class Instrumentation

    def self.format_time(seconds:, nanos: 0)
      return unless seconds
      Time.at(seconds, ((nanos || 0) / 10**3)).to_s
    end

    def self.instrument(key:, payload: {})
      GitHub.instrument(key, payload.compact)
    end

    def self.get_actor(actor_id:, actor_type:)
      ActiveRecord::Base.connected_to(role: :reading) do
        begin
          if actor_type == :ACTOR_TYPE_INSTALLATION
            if GitHub::CurrentTenant.get.present? || GitHub.multi_tenant_enterprise?
              value = IntegrationInstallation.find_by_id(actor_id)&.bot
              GitHub.logger.info(
                "Find integration installation by ID",
                "code.function" => __method__,
                "code.namespace" => self.class.name,
                "gh.registry.actor_id" => actor_id,
                "gh.registry.value" => value,
              )
            end
            return IntegrationInstallation.find_by_id(actor_id)&.bot
          elsif actor_type == :ACTOR_TYPE_SITE_SCOPED_INSTALLATION
            if GitHub::CurrentTenant.get.present? || GitHub.multi_tenant_enterprise?
              value = SiteScopedIntegrationInstallation.find_by_id(actor_id)&.bot
              GitHub.logger.info(
                "Find site scoped integration installation by ID",
                "code.function" => __method__,
                "code.namespace" => self.class.name,
                "gh.registry.actor_id" => actor_id,
                "gh.registry.value" => value,
              )
            end
            return SiteScopedIntegrationInstallation.find_by_id(actor_id)&.bot
          else
            if GitHub::CurrentTenant.get.present? || GitHub.multi_tenant_enterprise?
              value = User.find_by_id(actor_id)
              GitHub.logger.info(
                "Find user by ID",
                "code.function" => __method__,
                "code.namespace" => self.class.name,
                "gh.registry.actor_id" => actor_id,
                "gh.registry.value" => value,
              )
            end
            return User.find_by_id(actor_id)
          end
        rescue ActiveRecord::RecordNotFound => e
          if GitHub::CurrentTenant.get.present? || GitHub.multi_tenant_enterprise?
            GitHub.logger.info(
              "Active record not found for the audit log instrumentation",
              "code.function" => __method__,
              "code.namespace" => self.class.name,
            )
          end
          GitHub.logger.error(e)
        end
      end
    end

    def self.package_deleted(actor_id:, actor:, org_id: nil, org: nil, repo_id: nil, repo: nil, package_id:, package:, ecosystem:, version_count: nil, storage_bytes: nil, deleted_time:)
      instrument(
        key: "packages.package_deleted",
        payload: {
          actor_id: actor_id,
          actor: actor,
          org: org,
          org_id: org_id,
          repo: repo,
          repo_id: repo_id,
          package_id: package_id,
          package: package,
          ecosystem: ecosystem,
          version_count: version_count,
          storage_bytes: storage_bytes,
          deleted_time: deleted_time
        }
      )
    end

    def self.package_published(actor_id:, actor:, org_id: nil, org: nil, repo_id: nil, repo: nil, package_id:, package:, ecosystem:, storage_bytes: nil, version_count: nil, is_republished:, published_time:)
      if GitHub::CurrentTenant.get.present? || GitHub.multi_tenant_enterprise?
        GitHub.logger.info(
          "Sending package_published event",
          "code.function" => __method__,
          "code.namespace" => self.class.name,
        )
      end
      instrument(
        key: "packages.package_published",
        payload: {
          actor_id: actor_id,
          actor: actor,
          org: org,
          org_id: org_id,
          repo: repo,
          repo_id: repo_id,
          package_id: package_id,
          package: package,
          ecosystem: ecosystem,
          storage_bytes: storage_bytes,
          version_count: version_count,
          is_republished: is_republished,
          published_time: published_time
        }
      )
    end

    def self.package_version_deleted(actor_id:, actor:, org_id: nil, org: nil, repo_id: nil, repo: nil, package_id:, package:, ecosystem:, version_id:, version:, deleted_time:)
      instrument(
        key: "packages.package_version_deleted",
        payload: {
          actor_id: actor_id,
          actor: actor,
          org: org,
          org_id: org_id,
          repo: repo,
          repo_id: repo_id,
          package_id: package_id,
          package: package,
          ecosystem: ecosystem,
          version_id: version_id,
          version: version,
          deleted_time: deleted_time
        }
      )
    end

    def self.package_version_published(actor_id:, actor:, org_id: nil, org: nil, repo_id: nil, repo: nil, package_id:, package:, ecosystem:, storage_bytes: 0, version_id:, version:, published_time:, republished:)
      instrument(
          key: "packages.package_version_published",
          payload: {
              actor_id: actor_id,
              actor: actor,
              org_id: org_id,
              org: org,
              repo_id: repo_id,
              repo: repo,
              package_id: package_id,
              package: package,
              ecosystem: ecosystem,
              storage_bytes: storage_bytes,
              version_id: version_id,
              version: version,
              published_time: published_time,
              is_republished: republished
          }
      )
    end

    def self.v2_package_version_published(owner_id:, owner_name:, ecosystem:, package_id:, package_name:, version_id:, version_sha:, storage_bytes:, actor_id:, actor:, user_agent:, is_republished:)
      if GitHub::CurrentTenant.get.present? || GitHub.multi_tenant_enterprise?
        GitHub.logger.info(
          "Sending package_version_published event",
          "code.function" => __method__,
          "code.namespace" => self.class.name,
        )
      end
      instrument(
        key: "packages.package_version_published",
        payload: {
          org_id: owner_id,
          owner_name: owner_name,
          ecosystem: ecosystem,
          package_id: package_id,
          package: package_name,
          version_id: version_id,
          version: version_sha,
          storage_bytes: storage_bytes,
          actor_id: actor_id,
          actor: actor,
          user_agent: user_agent,
          is_republished: is_republished
        }
      )
    end

    def self.v2_package_version_deleted(owner_id:, owner_name:, ecosystem:, package_id:, package_name:, version_id:, version_sha:, storage_bytes:, actor_id:, actor:, user_agent:, deleted_time:)
      instrument(
        key: "packages.package_version_deleted",
        payload: {
          org_id: owner_id,
          owner_name: owner_name,
          ecosystem: ecosystem,
          package_id: package_id,
          package: package_name,
          version_id: version_id,
          version: version_sha,
          storage_bytes: storage_bytes,
          actor_id: actor_id,
          actor: actor,
          user_agent: user_agent,
          deleted_time: deleted_time,
        }
      )
    end
  end
end
