# typed: strict
# frozen_string_literal: true

class HydroModelsOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_models_on_push

  sig { returns(T.untyped) }
  def perform
    return if repository.nil? || repository.deleted?
    return unless GitHubModels::Repository.new(repository: repository).models_enabled_for_repo?
    default_branch_update = push_includes_default_branch?

    unless default_branch_update.present?
      GitHub.logger.info(
        "HydroModelsOnPushJob: no default branch update found",
        "gh.repo.id": repository.id,
        "gh.request_id": request_id,
      )
      return
    end

    if default_branch_update.deleted?
      GitHub.logger.info(
        "HydroModelsOnPushJob: default branch update is deleted",
        "gh.repo.id": repository.id,
        "gh.request_id": request_id,
      )
      return
    end

    with_write do
      if default_branch_update.large_push?
        # TODO: implement function refresh_prompts; this will called on large pushes, otherwise branch
        # to update_repository_prompts
        GitHub.logger.info(
          "HydroModelsOnPushJob: large push detected",
          "gh.repo.id": repository.id,
          "gh.request_id": request_id,
        )
      end

      update_repository_prompts(repository, default_branch_update.ref, default_branch_update.before, default_branch_update.after)
    end
  end

  PROMPT_FILE_REGEX = /\.prompt\.(yml|yaml)\z/

  sig { params(repository: ::Repository, ref: String, before: String, after: String).void }
  def update_repository_prompts(repository, ref, before, after)
    # When before is a null OID, the push is to a new repository
    # To ensure we get a diff for all the files added, we need to
    # use the EMPTY_TREE_OID rather than a null OID.
    before = GitHub::EMPTY_TREE_OID if before == GitHub::NULL_OID
    changed_files = repository.rpc.native_read_diff_toc(before, after, nil)

    if ref != "refs/heads/#{repository.default_branch}"
      return
    end

    # Preload prompts in repo to avoid n+1 queries
    preloaded_prompts = GitHubModels::Prompt.preload(:repository).for_repo(repository).index_by(&:path)

    # For now: we want to create, update, and remove prompt entities only when they
    # are pushed to the default branch
    changed_files.each do |changed_file|
      path = changed_file.path

      renamed = changed_file.status == Repositories::ChangedFile::RENAMING
      # Is the file currently considered a prompt?
      currently_a_prompt = path.match?(PROMPT_FILE_REGEX)
      # Was the file previously considered a prompt?
      was_a_prompt = changed_file.old_file.path.match?(PROMPT_FILE_REGEX)

      if renamed
        # For renames, we need to check the old file path as well the current to ensure
        # we delete the old prompt in cases where the new file is no longer a prompt
        next unless was_a_prompt || currently_a_prompt
      else
        next unless currently_a_prompt
      end

      if was_a_prompt
        deleted = changed_file.status == Repositories::ChangedFile::DELETION
        if renamed || deleted
          preloaded_prompts[changed_file.old_file.path]&.destroy
          preloaded_prompts.delete(changed_file.old_file.path)
          GitHub.dogstats.increment("repository.prompts.updated", tags: ["status:deleted"])
        end
      end

      # Don't try to create a new workflow entry if the file was renamed to a non-workflow file
      next if was_a_prompt && !currently_a_prompt

      added_or_modified = changed_file.status == Repositories::ChangedFile::ADDITION || changed_file.status == Repositories::ChangedFile::MODIFYING
      if added_or_modified || renamed
        parsed_prompt = GitHubModels::Prompts::ParsedPrompt.from_repo(repository, path)
        next unless parsed_prompt

        prompt = preloaded_prompts[path]
        if prompt
          prompt.update({
          name: parsed_prompt.name,
          description: parsed_prompt.description,
          model: parsed_prompt.model_name
          })
          GitHub.dogstats.increment("repository.prompts.updated", tags: ["status:modified"])
        else
          prompt = GitHubModels::Prompt.new({
            path: path,
            owner_id: T.must(repository.owner).id,
            repository: repository,
            name: parsed_prompt.name,
            description: parsed_prompt.description,
            model: parsed_prompt.model_name
          })
          prompt.save
          GitHub.dogstats.increment("repository.prompts.updated", tags: ["status:new"])
        end
      end
    end
  end

  # sig { returns(NilClass) }
  # def refresh_prompts

  # end
end
