# typed: false
# frozen_string_literal: true

# Transition to correct a variety of referential issues on repositories records.
#
#  - Records with NULL deleted column values are set 0 instead.
#  - Records whose parent_id value reference a record that doesn't exist or is
#    marked deleted are set to NULL.
#  - Records whose parent_id reference a repository that has a different
#    source_id (in a different network) are updated to set parent_id to NULL,
#    removing the linkage.
#  - Elects new root repositories when all records with the same source_id have
#    a parent_id value. At least one repository record must have a NULL
#    parent_id at all times.
#  - Sets parentage to a single root when a network has multiple root
#    repositories.
#
# Run this manually in production with something like:
#
#   $ ssh -t fe13-ext.rs.github.com
#   $ gh-screen
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/correct_bad_repository_source_references.rb
#
require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class CorrectBadRepositorySourceReferences

      # This transition is run from inside a db migration. Use a local model
      # instead of the latest Repository since this code runs at a specific
      # point in time and requires predictable code.
      class Repo < ApplicationRecord::Domain::Repositories
        self.table_name = "repositories"
        belongs_to :owner, class_name: "User"
        def name_with_owner
          "#{owner.login}/#{name}"
        end
      end

      # Correct a variety of issues with repositories record referential
      # integrity. The order of the operations here are pretty important.
      # Cleanup from one operation may effect the assumptions of the next.
      def perform
        correct_repositories_with_bad_parent_references
        correct_repositories_with_parents_in_other_network
        correct_networks_with_no_root
        correct_networks_with_multiple_public_roots
      end

      # Find all repositories records that have a parent_id value that doesn't
      # have a corresponding record or whose record is marked as deleted. The
      # parent_id is set to nil.
      def correct_repositories_with_bad_parent_references
        repos = find_repositories_with_bad_parent_references
        puts "correcting #{repos.size} repositories with bad parent_id references"

        repos.each do |repository_id|
          repo = Repo.find(repository_id)
          puts "-- #{repo.name_with_owner} set parent_id = NULL"
          repo.update_attribute :parent_id, nil
        end
      end

      # Finds all repositories records whose parent_id references a repository
      # in a different network (source_id is different) and sets their parent_id
      # to nil removing any linkage.
      def correct_repositories_with_parents_in_other_network
        repo_ids = find_repositories_with_parents_in_other_network
        puts "correcting #{repo_ids.size} repositories referencing parents in other networks"
        repo_ids.each do |repo_id|
          repo = Repo.find(repo_id)
          puts "-- #{repo.name_with_owner} removing parent reference to #{repo.parent.name_with_owner}"
          repo.update_attribute :parent_id, nil
        end
      end

      # Finds all networks that have no root repository and elect one to act as
      # the new root. The oldest repository in the network is elected.
      def correct_networks_with_no_root
        network_ids = find_networks_with_no_root
        puts "correcting #{network_ids.size} networks with no root"

        network_ids.each do |network_id|
          repo = Repository.active.where("source_id = ?", network_id).order("created_at ASC").first
          puts "-- #{repo.name_with_owner} elected as root of network #{network_id}"
          repo.update_attribute :parent_id, nil
        end
      end

      # Finds all networks that have multiple root records, elects one to be
      # the sole root, and updates all other record's parent_id to point at the
      # elected record.
      def correct_networks_with_multiple_public_roots
        network_ids = find_networks_with_multiple_public_roots
        puts "correcting #{network_ids.size} possible networks with multiple roots"

        network_ids.each do |network_id|
          repos = Repository \
            .active.where("source_id = ? AND public = 1 AND parent_id IS NULL", network_id)
            .order("created_at ASC")
            .to_a

          # bail if there's only root with the same visibility
          next if repos.size <= 1

          best = repos.shift
          puts "-- #{best.name_with_owner} reparenting #{repos.size} bad roots"
          repos.each do |repo|
            repo.update_attribute(:parent_id, best.id)
          end
        end
      end

      ##
      # Queries

      def find_repositories_with_bad_parent_references
        select_values "
          SELECT r.id
            FROM repositories r
           WHERE r.parent_id IS NOT NULL
             AND r.active = 1
             AND NOT EXISTS (
                   SELECT *
                     FROM repositories r2
                    WHERE r2.id = r.parent_id
                      AND r2.active = 1
                 )
        "
      end

      def find_repositories_with_parents_in_other_network
        select_values "
          SELECT r.id
            FROM repositories r
            JOIN repositories p ON p.id = r.parent_id
           WHERE p.source_id != r.source_id
        "
      end

      def find_networks_with_no_root
        select_values "
           SELECT source_id FROM (
             SELECT source_id,
                    SUM(
                      CASE WHEN parent_id IS NULL THEN 1
                      ELSE 0
                      END
                    ) AS root_count
               FROM repositories
              WHERE active = 1
              GROUP BY source_id
             HAVING root_count = 0
          ) q
        "
      end

      def find_networks_with_multiple_public_roots
        select_values "
          SELECT source_id FROM (
            SELECT source_id,
                   SUM(
                     CASE WHEN parent_id IS NULL THEN 1
                     ELSE 0
                     END
                   ) AS root_count
              FROM repositories
             WHERE active = 1 AND public = 1
             GROUP BY source_id
            HAVING root_count > 1
          ) q
        "
      end

      # Runs a SQL query and returns the result as an array of values. The query
      # is run on a replica database.
      def select_values(query)
        ActiveRecord::Base.connected_to(role: :reading) do
          Repository.connection.select_values(query)
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  trans = GitHub::Transitions::CorrectBadRepositorySourceReferences.new
  trans.perform
end
