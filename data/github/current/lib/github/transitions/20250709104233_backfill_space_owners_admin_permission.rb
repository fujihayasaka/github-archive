# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSpaceOwnersAdminPermission < Base
      # Most transitions iterate over a dataset. To do that, use and configure
      # an iterator using `iterate_over`. See the common database table
      # iterator example below, or check the iterators base class
      # (`GitHub::Transitions::Iterators::Base`) to learn how to implement
      # a custom iterator.
      #
      # In case you are not iterating over a dataset but want to perform a
      # one-off action, you can overwrite the `#perform` method.


      class Space < ApplicationRecord::Copilot
        self.table_name = :custom_copilots
      end

      iterate_over :database_table, params: {
        model_class: Space,
        conditions: "creator_id IS NOT NULL"
      }


      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        scope = CopilotSpace.where(id: items.keys)

        if dry_run?
          log "would update #{scope.count} spaces to give owners admin permission"
        else
          role = Role.custom_copilot_admin_role

          scope.each do |copilot_space|
            creator = copilot_space.creator
            next unless creator

            begin
              write_to(model_class: ::UserRole) do
                result = Permissions::Granters::RoleGranter.new(actor: creator, target: copilot_space, role: role).grant_unless_exists!

                if result.success?
                  log("Successfully processed item", id: copilot_space.id, role: role.name, actor_id: creator.id)
                else
                  log("Failure processing item", id: copilot_space.id, reason: result.reason)
                end
              end
            rescue Permissions::Granters::RoleGranter::GrantFailure => e
              log("Failure processing item", id: copilot_space.id, reason: e.message)
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

  GitHub::Transitions::BackfillSpaceOwnersAdminPermission.new(args).run
end
