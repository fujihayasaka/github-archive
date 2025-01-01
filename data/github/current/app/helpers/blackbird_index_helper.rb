# typed: strict
# frozen_string_literal: true

module BlackbirdIndexHelper
  # Causes blackbird to index embeddings for a repository's contents.
  # Indexes either docs (markdown only) or all code in the repo.
  #
  # Note: It is not obvious whether dotcom is necessarily the right place for
  # this to happen from a design perspective, rather than in CAPI. But for now,
  # the decision has been made that all clients will go through dotcom to manage
  # indexing.
  #     For now, there are two places this is kicked off: by clients using the
  # index_embeddings API, and during docset creation. If it later becomes the
  # case that other chat clients will *not* be going through dotcom for docset
  # management (i.e. if they directly interact with CAPI for this), then we
  # may want to re-evaluate.
  sig do
    params(
      user: User,
      repo: Repository,
      index_code: T.nilable(T::Boolean),
      index_docs: T.nilable(T::Boolean))
    .returns(Symbol)
  end
  def trigger_embeddings_indexing(user, repo, index_code: false, index_docs: false)
    return :ok unless index_code || index_docs

    status = can_index_embeddings_status(user, repo)
    return status unless status == :ok

    # This is a backstop limit to prevent abuse.
    if user.feature_enabled?(:blackbird_use_indexing_abuse_limits) && BlackbirdSearch::Redis.at_indexing_limit?(user.id)
      return :quota_exhausted
    end

    # Indexing is only allowed if the owner exists, so this is definitely not nil
    owner_id = repo.owner&.id

    # Create the CopilotIndexedRepositories record. Note that `find_or_create_by` will try to find a record with
    # the specified `repository_id`, even if the `markdown_only` column doesn't match. If the record exists with
    # `markdown_only` set to true, and we are indexing code, we must set it to false.
    cir = CopilotIndexedRepositories.find_or_create_by(repository_id: repo.id) do |cir|
      cir.organization_id = owner_id
      cir.markdown_only = !!index_docs
    end
    if cir.markdown_only && index_code
      cir.markdown_only = false
      cir.last_requested_at = Time.now.utc
      cir.save
    else
      cir.touch(:last_requested_at)
    end

    # Force reindexing
    BlackbirdOnboardReposJob.perform_later(user.id, [repo.id])

    # Log indexing to datadog and splunk
    GitHub.dogstats.increment("blackbird.embeddings.index")
    GitHub.logger.info("blackbird.embeddings.index", {
      "repository" => repo.name_with_display_owner,
      "owner" => T.must(repo.owner).display_login,
    })

    :ok
  end

  sig { params(user: User, repo: Repository).returns(Symbol) }
  def can_index_embeddings_status(user, repo)
    if !repo
      return :not_found
    end

    # Find the repository and ensure it is readable by the current user
    if !repo.readable_by?(user)
      return :not_found
    end

    # Only users with access to copilot in dotcom can call this
    if !Copilot::User::new(user).dotcom_chat_enabled?
      return :unauthorized
    end

    if GitHub.flipper[:embedding_indexing_unavailable].enabled?
      return :service_unavailable
    end

    # IMPORTANT: This is a hard limit due to capacity constraints (GPUs for computing embeddings, VMs and hard disk
    # space for storing these indices).
    if CopilotIndexedRepositories.count >= CopilotIndexedRepositories::MAX_INDEXED_REPOS
      return :service_unavailable
    end

    :ok
  end
end
