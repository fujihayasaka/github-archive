# typed: false
# frozen_string_literal: true

# RepositoryNetwork methods used during the great backfill of 2013.
#
# See: lib/github/transitions/backfill_repository_networks.rb for the
# backfill logic that uses this stuff.
class RepositoryNetwork
  module Backfill
    extend ActiveSupport::Concern

    class_methods do
      # Build a new RepositoryNetwork for a given network id using information from
      # the repositories table but don't save/create the record.
      #
      # network_id - The network id (repository.source_id value)
      #
      # Returns an unsaved RepositoryNetwork object.
      def backfill(network_id)
        network = new(network_id: network_id)
        network.recalculate
        network
      end

      # Like the non-bang method but also save the record.
      #
      # Returns a newly created and saved RepositoryNetwork object.
      def backfill!(network_id)
        network = backfill(network_id)
        network.save!
        network
      end
    end

    # Recalculate base repository_networks attributes by aggreating the information
    # in the repositories table. Used during the backfill/transition period and possibly
    # to recover from bad network information.
    #
    # Returns a Hash of attribute name => value pairs, or nil when no repos exist.
    def recalculate
      recalculate_attributes.each do |key, value|
        next if key.to_sym == :id
        send("#{key}=", value)
      end
      self.root_id = recalculate_root
    end

    # Recalculate stuff and save, raising an exception if the record can not be
    # found, validations fail, or a database error occurs.
    def recalculate!
      recalculate
      save!
    end

    # Generate a single recalculate record from information in the repositories
    # table. This is used to backfill initial RepositoryNetwork records and
    # should only be needed to resync bad data once the initial backfill is
    # complete.
    #
    # Returns a Hash of attribute name => value pairs, or nil when no repos exist.
    def recalculate_attributes
      fail "RepositoryNetwork#id must be set when calculating attributes" if id.nil?

      self.class.connection.select_all("
        SELECT source_id       AS id,
               MAX(pushed_at)  AS pushed_at,
               MIN(created_at) AS created_at,
               MAX(updated_at) AS updated_at
          FROM repositories
         WHERE source_id = #{id.to_i}
      GROUP BY source_id
      ").first&.to_h
    end

    # Determine the root repository for a network using the same approach as
    # Repository#source. This query is intense so we check the cache first.
    #
    # Returns the integer id of the root repository for this network.
    def recalculate_root
      if (repo_id = GitHub.cache.get("source-repo:#{id}"))
        repo_id
      else
        self.class.connection.select_value("
          SELECT id FROM repositories
          WHERE source_id = #{id.to_i}
            AND parent_id IS NULL
            AND active = 1
          ORDER BY id ASC LIMIT 1
        ")
      end
    end
  end
end
