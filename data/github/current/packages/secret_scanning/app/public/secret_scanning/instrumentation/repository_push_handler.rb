# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Instrumentation
  class RepositoryPushHandler
    # Handles a repository push event for Secret Scanning
    sig { params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(User)).void }
    def self.on_repository_push(repository, ref_updates, actor)
      return unless ref_updates.any?

      token_scanning = SecretScanning::Features::Repo::TokenScanning.new(repository)

      if token_scanning.enabled? && self.config_file_changed?(repository, ref_updates)
        # Fire hydro event for config change
        GlobalInstrumenter.instrument("token_scan.config_change", {
          repository: repository,
          owner: repository.owner,
          actor: actor,
        })
      end
    end

    # Indicates whether the Secret Scanning configuration file was changed
    sig { params(repository: Repository, ref_updates: T::Array[Git::Ref::Update]).returns(T::Boolean) }
    private_class_method def self.config_file_changed?(repository, ref_updates)
      ref_updates.any? do |ref_update|
        # make sure this update is going into master
        # ref_update.refname example: "refs/heads/master". Extracting "master" as the branch being merged into.
        update_branch = ref_update.refname.split("/")[-1]
        return false unless update_branch == repository.default_branch

        config_file_path = TokenScanningConfigurationFile::DEFAULT_NAME_PATH
        # update deletes the default branch, check to see if the tree contained the config file
        if ref_update.after_oid == GitHub::NULL_OID
          return repository.tree_file_list(ref_update.before_oid).include? config_file_path
        end

        # check if a config file was one of the changes
        changed_commit_diff = repository.commits.find(ref_update.after_oid).diff
        return true if changed_commit_diff.map { |file| file.path }.include? config_file_path

        # check if config was renamed
        changed_commit_diff.map { |file| file.a_path }.include? config_file_path
      end
    end
  end
end
