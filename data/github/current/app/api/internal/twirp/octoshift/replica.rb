# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift

  # Public: A utility class for ensuring replication delay is accounted for when reading from replicas.
  class Replica
    MAX_ATTEMPTS = 3

    # Public: Initialize a Replica.
    #
    # klass - An ActiveRecord::Base subclass.
    def initialize(klass)
      @klass = klass
    end

    # Public: Wraps ActiveRecord::Base#find_by to account for replication delay.
    #
    # args  - Arguments that are accepted by ActiveRecord::Base#find_by.
    #
    # Returns results from ActiveRecord::Base#find_by.
    # Raises Errors::HighReplicationDelay not found and excessive replication delay.
    def find_by(*args) # rubocop:disable GitHub/FindByDef
      if GitHub.flipper[:octoshift_replica_reads].enabled?
        counter = MAX_ATTEMPTS

        replica do
          result = klass.find_by(*args)

          unless result || (counter -= 1).zero?
            account_for_replication_delay!
            raise Errors::BecauseSorbetDoesntSupportRedo
          end

          result
        rescue Errors::BecauseSorbetDoesntSupportRedo
          retry # rubocop:disable GitHub/UnboundedRetries
        end
      else
        ActiveRecord::Base.connected_to(role: :writing) do
          klass.find_by(*args)
        end
      end
    end

    # Public: Wraps ActiveRecord::Base#find_by! to account for replication delay.
    #
    # args  - Arguments that are accepted by ActiveRecord::Base#find_by!.
    #
    # Returns Returns results from ActiveRecord::Base#find_by!.
    # Raises Errors::HighReplicationDelay not found and excessive replication delay.
    def find_by!(*args) # rubocop:disable GitHub/FindByDef
      if GitHub.flipper[:octoshift_replica_reads].enabled?
        counter = MAX_ATTEMPTS

        replica do
          klass.find_by!(*args)
        rescue ActiveRecord::RecordNotFound
          unless (counter -= 1).zero?
            account_for_replication_delay!
            retry
          end

          raise
        end
      else
        ActiveRecord::Base.connected_to(role: :writing) do
          klass.find_by!(*args)
        end
      end
    end

    # Public: allows safe replica querying on the replica for the class
    #
    # args  - block to run with the class
    #
    # Returns results from your block
    # Raises Errors::HighReplicationDelay not found and excessive replication delay.
    def query
      if GitHub.flipper[:octoshift_replica_reads].enabled?
        replica do
          account_for_replication_delay!

          yield(klass)
        end
      else
        ActiveRecord::Base.connected_to(role: :writing) do
          yield(klass)
        end
      end
    end

    private

    attr_reader :klass

    def account_for_replication_delay!
      raise Errors::HighReplicationDelay.new(replication_delay, role) if replication_delay > max_replication_delay

      Kernel.sleep sleep_time
    end

    def sleep_time
      replication_delay / 1000.0
    end

    def replica
      ActiveRecord::Base.connected_to(role: role) do
        yield
      end
    end

    def role
      :reading
    end

    def replication_delay
      klass.default_replication_wait
    end

    def max_replication_delay
      GitHub.octoshift_freno_max_replication_delay_ms
    end
  end
end
