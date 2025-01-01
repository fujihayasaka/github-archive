# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillAppManagementWithRbac < Base

      ORG_APP_MANAGER_SUBJECT_TYPE = T.let("Organization/manage_apps", String)

      MANAGEMENT_SUBJECT_TYPES = T.let(
        [ORG_APP_MANAGER_SUBJECT_TYPE, "Integration/manage"],
        T::Array[String]
      )

      class Permission < ApplicationRecord::Domain::Permissions
        self.table_name = :permissions
      end

      class CustomIterator < GitHub::Transitions::Iterators::Base
        DEFAULT_PROCESS_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 10000 : 100, Integer
        )

        sig do
          override.params(
            block: T.proc.params(items: GitHub::Transitions::Iterators::Identifiers).void
          ).void
        end
        def each_identifiers_batch(&block)
          last_processed_id = arguments[:last_processed_id].to_i

          while ids = load_ids(last_processed_id)
            yield ids
            last_processed_id = ids.last

            return unless last_processed_id
          end
        end

        sig do
          override.params(
            identifiers: GitHub::Transitions::Iterators::Identifiers
          ).returns(GitHub::Transitions::Iterators::Items)
        end
        def build_items_for_batch(identifiers)
          Permission
            .where(id: identifiers)
            .pluck(:id, :actor_id, :subject_id, :subject_type)
            .each_with_object({}) do |(id, actor_id, subject_id, subject_type), items|
              items[id] = {
                actor_id: actor_id,
                subject_id: subject_id,
                subject_type: subject_type,
              }
            end
        end

        sig { params(last_processed_id: Integer).returns(GitHub::Transitions::Iterators::Identifiers) }
        def load_ids(last_processed_id)
          Permission
            .where(subject_type: MANAGEMENT_SUBJECT_TYPES)
            .where(actor_type: "User")
            .where("id > ?", last_processed_id)
            .order(:id)
            .limit(process_batch_size)
            .pluck(:id)
        end

        sig { returns(Integer) }
        def process_batch_size
          arg = arguments[:process_batch_size].to_i
          return DEFAULT_PROCESS_BATCH_SIZE if arg.zero?

          arg
        end
      end

      iterate_over CustomIterator

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        item_ids = items.keys
        log("Processing batch", size: items.size, start_id: item_ids.first, end_id: item_ids.last)

        actor_ids = items.values.map { |attrs| attrs[:actor_id] }
        actors = User.unscoped.where(id: actor_ids).index_by(&:id)

        business_ids = actors.values.map(&:business_id).compact
        businesses = Business.where(id: business_ids).index_by(&:id)

        items.each do |id, attrs|
          actor_id = attrs.fetch(:actor_id)
          subject_id = attrs.fetch(:subject_id)
          subject_type = attrs.fetch(:subject_type)

          role = if subject_type == ORG_APP_MANAGER_SUBJECT_TYPE
            Role.app_manager_role
          else
            Role.app_owner_role
          end

          actor = actors[actor_id]
          next log("Failure processing item", id: id, reason: "Actor not found") unless actor

          if GitHub.multi_tenant_enterprise? && tenant = businesses[actor.business_id]
            GitHub::CurrentTenant.set(tenant)
          end

          target = if subject_type == ORG_APP_MANAGER_SUBJECT_TYPE
            ::Organization.unscoped.find_by(id: subject_id)
          else
            ::Integration.find_by(id: subject_id)
          end
          next log("Failure processing item", id: id, reason: "Target not found") unless target

          if dry_run?
            log("Would process item", id: id, role: role.name, actor_id: actor.id, target_id: target.id, target_type: target.class.name)
          else
            begin
              write_to(model_class: ::UserRole) do
                result = Permissions::Granters::RoleGranter
                  .new(actor:, target:, role:)
                  .grant_unless_exists!

                if result.success?
                  log("Successfully processed item", id: id, role: role.name, actor_id: actor.id, target_id: target.id, target_type: target.class.name)
                else
                  log("Failure processing item", id: id, reason: result.reason)
                end
              end
            rescue Permissions::Granters::RoleGranter::GrantFailure => e
              log("Failure processing item", id: id, reason: e.message)
            end
          end
          GitHub::CurrentTenant.reset if GitHub.multi_tenant_enterprise?
        end

        log("Finished batch", size: items.size)
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

  GitHub::Transitions::BackfillAppManagementWithRbac.new(args).run
end
