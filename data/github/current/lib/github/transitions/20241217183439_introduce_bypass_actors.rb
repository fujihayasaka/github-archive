# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class IntroduceBypassActors < Base
      ORG_BYPASS_NONE = 4
      ORG_BYPASS_PRS_ONLY = 5
      ORG_BYPASS_ANY = 6

      iterate_over :database_table, params: {
        model_class: RepositoryRuleset,
        conditions: "bypass_prohibited > #{ORG_BYPASS_NONE} OR deploy_key_bypass > 0",
        columns: %i[bypass_prohibited deploy_key_bypass],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        process_deploy_keys(items)
        process_org_admins(items)
      end

      sig { params(items: Iterators::Items).void }
      def process_deploy_keys(items)
        ruleset_ids = RepositoryRuleset.where(id: items.keys).where("deploy_key_bypass > 0").pluck(:id)

        # avoid inserting duplicates
        existing_ids = RepositoryRulesetBypassActor.where(repository_ruleset_id: ruleset_ids, type: "DeployKeyBypassActor").pluck(:repository_ruleset_id)
        ruleset_ids -= existing_ids

        rows = ruleset_ids.map do |id|
          {
            type: "DeployKeyBypassActor",
            actor_id: nil,
            actor_type: nil,
            repository_ruleset_id: id,
            bypass_mode: 0
          }
        end

        if dry_run?
          log "would insert #{ruleset_ids.count} rows of DeployKeyBypassActor"
        else
          log "inserting #{ruleset_ids.count} rows of DeployKeyBypassActor"
          write_to(model_class: RepositoryRulesetBypassActor) do
            RepositoryRulesetBypassActor.insert_all(rows)
          end
        end
      end

      sig { params(items: Iterators::Items).void }
      def process_org_admins(items)
        scope = RepositoryRuleset.where(id: items.keys).where("bypass_prohibited > #{ORG_BYPASS_NONE}").pluck(:id, :bypass_prohibited)
        ruleset_ids = scope.map(&:first)

        # avoid inserting duplicates
        existing_ids = RepositoryRulesetBypassActor.where(repository_ruleset_id: ruleset_ids, type: "OrganizationAdminBypassActor").pluck(:repository_ruleset_id)
        scope.reject! { |s| existing_ids.include?(s.first) }

        rows = scope.map do |id, bypass|
          {
            type: "OrganizationAdminBypassActor",
            actor_id: nil,
            actor_type: nil,
            repository_ruleset_id: id,
            bypass_mode: bypass == ORG_BYPASS_PRS_ONLY ? 1 : 0
          }
        end

        if dry_run?
          log "would insert #{scope.count} rows of OrganizationAdminBypassActor"
        else
          log "inserting #{scope.count} rows of OrganizationAdminBypassActor"
          write_to(model_class: RepositoryRulesetBypassActor) do
            RepositoryRulesetBypassActor.insert_all(rows)
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::IntroduceBypassActors.new(args).run
end
