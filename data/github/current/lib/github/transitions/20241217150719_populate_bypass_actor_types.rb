# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class PopulateBypassActorTypes < Base

      class BypassActor < ApplicationRecord::Domain::Repositories
        self.table_name = :repository_ruleset_bypass_actors
      end

      iterate_over :database_table, params: {
        model_class: BypassActor,
        conditions: "type IS NULL"
      }

      sig { override.params(items: T::Hash[T.any(Numeric, String), T::Hash[Symbol, T.untyped]]).void }
      def process_batch(items)
        actor_types = %w[RepositoryRole Team EnterpriseTeam EnterpriseOwner Integration]

        actor_types.each do |actor_type|
          scope = BypassActor.where(id: items.keys).where(type: nil, actor_type:)
          type = actor_type + "BypassActor"

          if dry_run?
            log "would update #{scope.count} rows for #{actor_type}"
          else
            log "updating #{scope.count} rows for #{actor_type}"
            write_to(model_class: BypassActor) do
              if actor_type == "EnterpriseOwner"
                # we need to clear the actor_id and actor_type entries for EnterpriseOwner
                # since they are not valid ActiveRecord objects, and we don't need it anymore.
                scope.update_all(type: type, actor_id: nil, actor_type: nil)
              else
                scope.update_all(type: type)
              end
            end
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

  GitHub::Transitions::PopulateBypassActorTypes.new(args).run
end
