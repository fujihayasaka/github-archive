# typed: false
# frozen_string_literal: true

module GitHub
  class DGit
    module Rebalancer
      # The base class defines the public method for the network and gist
      # rebalancer classes, as well as a few common methods between the
      # two classes.
      class Base
        def rebalance
          weights = choose_read_weights
          if all_replicas.any? { |repl| repl.read_weight != weights.fetch(repl.host) }
            assign_readweights weights
          end
        end

        def allocator
          @allocator ||= ReadWeightAllocator.new
        end
        attr_writer :allocator

        private

        # This generates a SQL string like this:
        #
        #   SET read_weight = CASE host WHEN 'dgit1' THEN 100 WHEN 'dgit2' THEN 0 END
        def set_weights_sql(sql, weights)
          sql.add "SET read_weight = CASE host"
          weights.each do |host, weight|
            sql.add "WHEN :host THEN :weight", host: host, weight: weight
          end
          sql.add "END"
        end
      end

      # Given a network_id and optionally a list of the current replicas,
      # update the database with readweights that satisfy our design goals.
      # Uses ReadWeightAllocator to figure out what the right weights are.
      class Network < Base
        def initialize(network_id, replicas: nil, new_host: nil)
          @network_id = network_id
          @all_replicas = replicas
          @new_host = new_host
        end

        private

        attr_reader :network_id, :new_host

        def choose_read_weights
          weights = allocator.choose_read_weights(all_replicas, new_host: new_host)
        end

        def all_replicas
          @all_replicas ||= GitHub::DGit::Routing.all_network_replicas(network_id)
        end

        def assign_readweights(weights)
          ActiveRecord::Base.connected_to(role: :writing) do
            sql = GitHub::DGit::DB.for_network_id(network_id).SQL.new "UPDATE network_replicas"
            set_weights_sql sql, weights
            sql.add <<-SQL, network_id: network_id, hosts: weights.keys
              WHERE network_id = :network_id
                AND host IN :hosts
            SQL
            sql.run
          end
        end
      end

      # Given a gist_id and optionally a list of the current replicas,
      # update the database with readweights that satisfy our design goals.
      # Uses ReadWeightAllocator to figure out what the right weights are.
      class Gist < Base
        def initialize(gist_id, replicas: nil, **args)
          @gist_id = gist_id
          @all_replicas = replicas
        end

        private

        attr_reader :gist_id

        def choose_read_weights
          weights = allocator.choose_read_weights(all_replicas)
        end

        def all_replicas
          @all_replicas ||= GitHub::DGit::Routing.all_gist_replicas(gist_id)
        end

        def assign_readweights(weights)
          ActiveRecord::Base.connected_to(role: :writing) do
            sql = GitHub::DGit::DB.for_gist_id(gist_id).SQL.new "UPDATE gist_replicas", gist_id: gist_id
            set_weights_sql sql, weights
            sql.add <<-SQL, hosts: weights.keys
              WHERE gist_id = :gist_id
                AND host IN :hosts
            SQL
            sql.run
          end
        end
      end
    end
  end
end
