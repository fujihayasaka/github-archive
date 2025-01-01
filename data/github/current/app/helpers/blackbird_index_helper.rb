# typed: strict
# frozen_string_literal: true

module BlackbirdIndexHelper
  # DEPRECATED: Use `trigger_embeddings_indexing_v2` instead.
  #
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

  # Create an embeddings index for the given repository.
  #
  # The repo must be readable by the user, and the user must have a valid Copilot license. In order for a repo to be
  # indexed with embeddings, it must have a row in the `copilot_indexed_repositories` table and blackbird needs to
  # crawl the repo. This is initiated by queuing a job that publishes a hydro event to blackbird.
  #
  # Returns a http status symbol:
  #
  # Success:
  # - :created: a job was queued to index the repo. This repo has not been indexed before.
  # - :accepted: a job was queued to reindex the repo. This repo has been indexed before, but a new job was queue to
  #   reindex.
  # - :no_content: the repo has already been indexed, and no new job was queued.
  #
  # Errors:
  # - :unauthorized: the user does not have a valid Copilot license.
  # - :not_found: the repo is not readable by the user.
  # - :too_many_requests: the user has exceeded their indexing rate limit. try again later.
  # - :service_unavailable: the repo cannot be indexed right now due to a system limit.
  sig do
    params(
      user: User,
      repo: Repository,
      force: T.nilable(T::Boolean),
    )
    .returns(Symbol)
  end
  def trigger_embeddings_indexing_v2(user, repo, force: false)
    # Hard limit due to capacity constraints (GPUs for embeddings, VMs and hard drives for storing indices).
    return :service_unavailable if CopilotIndexedRepositories.count >= CopilotIndexedRepositories::MAX_INDEXED_REPOS
    # For emergency use in the case of an incident.
    return :service_unavailable if FeatureFlag.vexi.enabled?(:embedding_indexing_unavailable, default: false)

    return :not_found unless force || repo.readable_by?(user)
    return :unauthorized unless force || Copilot::User::new(user).dotcom_chat_enabled?

    # indexing only allowed if the owner exists
    owner = T.must(repo.owner)

    cir = CopilotIndexedRepositories.find_or_initialize_by(repository_id: repo.id)
    if cir.new_record?
      # This is a backstop limit to prevent abuse.
      hit_abuse_limit = user.feature_enabled?(:blackbird_use_indexing_abuse_limits) && BlackbirdSearch::Redis.at_indexing_limit?(user.id)
      return :too_many_requests if !force && hit_abuse_limit

      cir.organization_id = owner.id
      cir.markdown_only = false
      cir.save

      # Queue a job to index the repo
      BlackbirdOnboardReposJob.perform_later(user.id, [repo.id])
      GitHub.dogstats.increment("blackbird.embeddings.index", tags: ["reindex:false"])
      GitHub.logger.info("blackbird.embeddings.index", {
        "repository" => repo.name_with_display_owner,
        "owner" => owner.display_login,
        "actor" => user.display_login,
        "reindex" => false,
      })
      :created
    else
      # Track repo activity
      cir.touch(:last_requested_at)

      # Repo should already be indexed, queue a job to reindex it if the force flag is set
      if force
        BlackbirdOnboardReposJob.perform_later(user.id, [repo.id])
        GitHub.dogstats.increment("blackbird.embeddings.index", tags: ["reindex:true"])
        GitHub.logger.info("blackbird.embeddings.index", {
          "repository" => repo.name_with_display_owner,
          "owner" => owner.display_login,
          "actor" => user.display_login,
          "reindex" => true,
        })
        :accepted
      else
        :ok
      end
    end
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

    if FeatureFlag.vexi.enabled?(:embedding_indexing_unavailable, default: false)
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
