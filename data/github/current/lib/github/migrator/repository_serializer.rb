# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class RepositorySerializer < BaseSerializer
      include Repositories::Domain::Provider

      def scope
        Repository.preload(:network, :owner, :labels, :projects, :public_keys, :configuration_entries)
      end

      def as_json(options = {})
        if org_metadata_only
          return {
            type: "repository",
            url: url,
            name: name,
          }
        end

        hash = {
          type: "repository",
          url: url,
          owner: owner,
          name: name,
          description: description,
          website: website,
          # on github.com, private? costs ~ 5 queries the first time it's called.
          private: private?,
          has_issues: has_issues?,
          has_wiki: has_wiki?,
          has_downloads: has_downloads?,
          is_archived: is_archived?,
          labels: labels,
          collaborators: collaborators,
          created_at: created_at,
          git_url: git_url,
          default_branch: default_branch,
          webhooks: webhooks,
          page: page,
          public_keys: public_keys,
          repository_topics: repository_topics,
          security_and_analysis: security_and_analysis,
          autolinks: autolinks,
          general_settings: general_settings,
          actions_general_settings: actions_general_settings,
        }

        hash[:wiki_url] = wiki_url if has_wiki? && wiki_exists?

        if GitHub.anonymous_git_access_enabled?
          hash[:anonymous_access_enabled] = anonymous_git_access_enabled?
        end

        hash
      end

      private

      def owner
        url_for_model(model.owner)
      end

      def name
        model.name
      end

      def description
        model.description
      end

      def website
        model.homepage
      end

      def private?
        model.private?
      end

      def has_issues?
        model.has_issues?
      end

      def has_wiki?
        model.has_wiki?
      end

      def has_downloads?
        model.has_downloads?
      end

      def is_archived?
        model.archived?
      end

      def labels
        model.labels.map do |label|
          {
            url: url_for_model(label),
            name: label.name,
            color: label.color,
            description: label.description,
            created_at: time(label.created_at),
          }
        end
      end

      def collaborators
        model.members.map do |member|
          {
            user: url_for_model(member),
            permission: model.access_level_for(member).to_s,
          }
        end
      end

      def git_url
        "tarball://root/repositories/#{model.owner.login}/#{name}.git"
      end

      def wiki_exists?
        model.unsullied_wiki.exist?
      end

      def wiki_url
        "tarball://root/repositories/#{model.owner.login}/#{name}.wiki.git"
      end

      def default_branch
        model.default_branch
      end

      def webhooks
        if model.repo_hook_associations_ff?
          Hook.hooks_for_target(model).map do |webhook|
            {
              payload_url: webhook.url,
              content_type: webhook.content_type,
              event_types: webhook.events,
              enable_ssl_verification: webhook.insecure_ssl == "0",
              active: webhook.active,
            }
          end
        else
          model.hooks.map do |webhook|
            {
              payload_url: webhook.url,
              content_type: webhook.content_type,
              event_types: webhook.events,
              enable_ssl_verification: webhook.insecure_ssl == "0",
              active: webhook.active,
            }
          end
        end
      end

      def page
        repository_page = model.page
        return if repository_page.nil?

        {
          cname: repository_page.cname,
          https_redirect: repository_page.https_redirect,
          source: repository_page.source,
          source_ref_name: repository_page.source_ref_name,
          source_subdir: repository_page.source_subdir,
          is_public: repository_page.public?,
          subdomain: repository_page.subdomain,
          parent_domain: repository_page.parent_domain,
          theme: nil,
          build_type: repository_page.build_type,
        }
      end

      def public_keys
        model.public_keys.map do |public_key|
          {
            title: public_key.title,
            key: public_key.key,
            read_only: public_key.read_only,
            fingerprint: public_key.fingerprint,
            created_at: time(public_key.created_at),
          }
        end
      end

      def anonymous_git_access_enabled?
        model.anonymous_git_access_enabled?
      end

      def repository_topics
        model.repository_topics.map do |repository_topic|
          attributes = repository_topic.migration_attributes
          attributes[:creator] = url_for_model(attributes[:creator])
          attributes[:repository] = url_for_model(attributes[:repository])
          attributes
        end
      end

      def security_and_analysis
        {
          dependency_graph: SecurityProduct::DependencyGraph.new(model).enabled?,
          vulnerability_alerts: SecurityProduct::VulnerabilityAlerts.new(model).enabled?,
          vulnerability_updates: SecurityProduct::VulnerabilityUpdates.new(model).enabled?,
          advanced_security: SecurityProduct::AdvancedSecurity.new(model).enabled?,
          token_scanning: SecurityProduct::TokenScanning.new(model).enabled?,
          token_scanning_push_protection: SecurityProduct::TokenScanningPushProtection.new(model).enabled?
        }
      end

      def autolinks
        repositories_domain.key_links.list_for_repo(model.id).to_a.map do |key_link|
          {
            key_prefix: key_link.key_prefix,
            url_template: key_link.url_template,
            is_alphanumeric: key_link.is_alphanumeric?
          }
        end
      end

      def general_settings
        {
          template: model.template?,
          allow_forking: model.allow_private_repository_forking?,
          sponsorships: model.repository_funding_links_enabled?,
          projects: model.projects_enabled?,
          discussions: model.discussions_on?,
          merge_commit: model.merge_commit_allowed?,
          squash_merge: model.squash_merge_allowed?,
          rebase_merge: model.rebase_merge_allowed?,
          auto_merge: model.auto_merge_allowed?,
          delete_branch_heads: model.delete_branch_on_merge?,
          update_branch: model.enable_update_branch?,
          git_lfs_in_archives: model.lfs_in_archives_enabled?
        }
      end

      def actions_general_settings
        {
          actions_disabled: model.actions_disabled?,
          allows_all_actions: model.allows_all_actions?,
          allows_local_actions_only: model.allows_local_actions_only?.nil? ? false : model.allows_local_actions_only?,
          allows_github_owned_actions: model.allows_github_owned_actions?.nil? ? false : model.allows_github_owned_actions?,
          allows_verified_actions: model.allows_verified_actions?.nil? ? false : model.allows_verified_actions?,
          allows_specific_actions_patterns: model.allows_specific_actions_patterns?.nil? ? false : model.allows_specific_actions_patterns?,
          patterns: model.actions_allowlist.present? ? model.actions_allowlist.allowed_action_patterns.pluck(:value) : []
        }
      end
    end
  end
end
