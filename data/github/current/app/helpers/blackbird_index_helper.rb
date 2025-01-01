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

    # Indexing is only allowed if the owner exists, so this is definitely not nil
    owner_id = T.must(repo.owner&.id)

    # Create the CopilotIndexedRepositories record. Note that `find_or_create_by` will try to find a record with
    # the specified `repository_id`, even if the `markdown_only` column doesn't match. If the record exists with
    # `markdown_only` set to true, and we are indexing code, we must set it to false.
    cir = CopilotIndexedRepositories.find_or_create_by(repository_id: repo.id) do |cir|
      cir.organization_id = owner_id
      cir.markdown_only = !!index_docs
    end
    if cir.markdown_only && index_code
      cir.markdown_only = false
      cir.save
    end

    # Force reindexing
    BlackbirdOnboardReposJob.perform_later(T.must(user.id), [T.must(repo.id)])

    :ok
  end

  sig { params(user: User, repo: Repository, check_quota: T.nilable(T::Boolean)).returns(Symbol) }
  def can_index_embeddings_status(user, repo, check_quota = true)
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

    if check_quota && CopilotIndexedRepositories.count >= CopilotIndexedRepositories::MAX_INDEXED_REPOS
      return :service_unavailable
    end

    copilot_public_user = Copilot::Public::User::new(user)

    if user.feature_enabled?(:copilot_dotcom_chat_ci_and_cb) && copilot_public_user.has_ci_access?
      if check_quota
        indexed = user.settings.get(:copilot_indexed_repo_count)
        available = CopilotIndexedRepositories::DEFAULT_COPILOT_INDIVIDUAL_INDEXING_QUOTA
        if indexed >= available
          return :quota_exhausted
        end
      end
    elsif !user.feature_enabled?(:bypass_copilot_indexing_limitations) || (user.feature_enabled?(:copilot_dotcom_chat_ci_and_cb) && copilot_public_user.has_cb_access? && !copilot_public_user.has_ce_access?)
      # If limitations are enforced, only allow indexing of repositories which
      # are owned by a copilot organization.
      orgs = Copilot::User.new(user).copilot_organizations
      owner = repo.owner

      if !owner || !orgs.include?(owner)
        return :forbidden
      end

      if !user.feature_enabled?(:bypass_org_admin_for_embeddings_indexing)
        is_org_admin = owner.adminable_by?(user)
        business = repo.business
        is_enterprise_admin = business && business.owner?(user)
        if !is_org_admin && !is_enterprise_admin
          return :unauthorized
        end
      end

      if check_quota
        indexed = CopilotIndexedRepositories.where(organization_id: owner.id, markdown_only: false).count
        available = CopilotIndexedRepositories::DEFAULT_COPILOT_INDEXING_QUOTA
        if owner.feature_enabled?(:copilot_expanded_indexing_quota)
          available *= 2
        end

        if indexed >= available
          return :quota_exhausted
        end
      end
    end

    :ok
  end
end
