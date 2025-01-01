# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryPreferredFiles < Platform::Loader
      def self.load(repository)
        self.for.load([repository.id, repository.owner_id])
      end

      def fetch(repo_and_owner_ids)
        repo_ids = repo_and_owner_ids.map(&:first).uniq
        owner_ids = repo_and_owner_ids.map(&:second).uniq

        # Load the IDs of the global file repositories for the owner of these
        # repositories
        global_promises = owner_ids.map { |id| GlobalHealthFilesRepository.load(id) }
        global_file_repo_ids_by_owner_id = Promise.all(global_promises).sync
          .compact
          .pluck(:owner_id, :id)
          .to_h

        # Load all known preferred files, both from local and global repositories
        all_repo_ids = repo_ids + global_file_repo_ids_by_owner_id.values
        preferred_files_by_repo_id = RepositoryPreferredFile.where(
          repository_id: all_repo_ids
        ).group_by(&:repository_id)

        repo_and_owner_ids.each_with_object(Hash.new) do |repo_and_owner_id, hash|
          repo_id, owner_id = repo_and_owner_id
          global_repo_id = global_file_repo_ids_by_owner_id[owner_id]

          files = []

          # add in local files, if any exist
          local_files = preferred_files_by_repo_id[repo_id] || []
          files = files + local_files

          # if there is a global repository, and it isn't the same as the
          # repository we are actually getting files for, add the global files
          if global_repo_id.present? && global_repo_id != repo_id
            global_files = preferred_files_by_repo_id[global_repo_id] || []
            files = files + global_files
          end

          hash[repo_and_owner_id] = files
        end
      end
    end
  end
end
