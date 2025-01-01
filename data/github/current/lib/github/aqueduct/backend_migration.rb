# typed: true
# frozen_string_literal: true

# Migrate to yukon from `gh-console master` with:
#
#   require "github/aqueduct/backend_migration"
#
#   # Preview changes
#   GitHub::Aqueduct::BackendMigration.migrate(to: :yukon, noop: true)
#
#   # Run migration
#   GitHub::Aqueduct::BackendMigration.migrate(to: :yukon, noop: false)
#
#   # Run migration, but prompt to proceed with each step.
#   GitHub::Aqueduct::BackendMigration.migrate(to: :yukon, noop: false, prompt: true)
#
# Migrate to hudson from `gh-console master` with:
#
#   require "github/aqueduct/backend_migration"
#   GitHub::Aqueduct::BackendMigration.migrate(to: :hudson, noop: true)
#   GitHub::Aqueduct::BackendMigration.migrate(to: :hudson, noop: false)
#
module GitHub
  module Aqueduct
    module BackendMigration
      SEND_FLAG = "aqueduct_enqueue_to_secondary"
      WORKER_FLAG = "use_secondary_aqueduct_backend"
      DFS_WORKER_FLAG = "use_secondary_aqueduct_backend_fsworker"

      STEPS = [
        { SEND_FLAG => 0,   WORKER_FLAG => 2,  DFS_WORKER_FLAG => 10 }, # fully hudson
        { SEND_FLAG => 15,  WORKER_FLAG => 15, DFS_WORKER_FLAG => 50 },
        { SEND_FLAG => 30,  WORKER_FLAG => 30, DFS_WORKER_FLAG => 50 },
        { SEND_FLAG => 45,  WORKER_FLAG => 45, DFS_WORKER_FLAG => 50 },
        { SEND_FLAG => 60,  WORKER_FLAG => 60, DFS_WORKER_FLAG => 50 },
        { SEND_FLAG => 75,  WORKER_FLAG => 75, DFS_WORKER_FLAG => 50 },
        { SEND_FLAG => 90,  WORKER_FLAG => 90, DFS_WORKER_FLAG => 50 },
        { SEND_FLAG => 100, WORKER_FLAG => 98, DFS_WORKER_FLAG => 90 }, # fully yukon
      ]

      def self.validate_actor_flag(flag, expected)
        enabled = GitHub.flipper[flag].percentage_of_actors_value
        if enabled != expected
          raise "Error: #{flag} isn't in the expected initial state of #{expected}, was #{enabled}"
        end
      end

      def self.validate_dark_ship_flag(flag, expected)
        enabled = GitHub.flipper[flag].percentage_of_time_value
        if enabled != expected
          raise "Error: #{flag} isn't in the expected initial state of #{expected}, was #{enabled}"
        end
      end

      def self.set_actor_flag(flag, value, noop)
        puts "Setting #{flag} to #{value}% of actors noop=#{noop}"
        GitHub.flipper[flag].enable_percentage_of_actors(value) unless noop
      end

      def self.set_dark_ship_flag(flag, value, noop)
        puts "Setting #{flag} to #{value}% of actors noop=#{noop}"
        GitHub.flipper[flag].enable_percentage_of_time(value) unless noop
      end

      def self.migrate(to:, noop: true, prompt: false)
        case to
        when :hudson
          steps = STEPS.reverse
        when :yukon
          steps = STEPS
        else
          raise "Error: Unexpected cluster #{to}"
        end

        initial = steps[0]
        validate_actor_flag(WORKER_FLAG, initial[WORKER_FLAG])
        validate_dark_ship_flag(DFS_WORKER_FLAG, initial[DFS_WORKER_FLAG])
        validate_dark_ship_flag(SEND_FLAG, initial[SEND_FLAG])

        steps[1..-1].each do |step|
          set_actor_flag(WORKER_FLAG, step.fetch(WORKER_FLAG), noop)
          set_dark_ship_flag(DFS_WORKER_FLAG, step.fetch(DFS_WORKER_FLAG), noop)

          sleep 10 # migrate worker capacity slightly before migrating enqueues

          set_dark_ship_flag(SEND_FLAG, step.fetch(SEND_FLAG), noop)

          unless step == steps.last
            # wait between steps
            if prompt
              puts "Press Enter to continue with the migration"
              gets
            else
              puts "Waiting 30 seconds before proceeding with the migration"
              sleep 30
            end
          end
        end

        puts "Done!"
      end
    end
  end
end
