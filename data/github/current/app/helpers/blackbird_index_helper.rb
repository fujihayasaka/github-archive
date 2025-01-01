# typed: true
# frozen_string_literal: true

module BlackbirdIndexHelper
  extend T::Sig
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

    # If limitations are enforced, only allow indexing of repositories which
    # are owned by a copilot organization.
    if !GitHub.flipper[:bypass_copilot_indexing_limitations].enabled?(user)
      orgs = Copilot::User.new(user).copilot_organizations
      owner = repo.owner

      if !owner || !orgs.include?(owner)
        return :forbidden
      end

      is_org_admin = owner.adminable_by?(user)
      business = repo.business
      is_enterprise_admin = business && business.owner?(user)
      if !is_org_admin && !is_enterprise_admin && !GitHub.flipper[:bypass_org_admin_for_embeddings_indexing].enabled?(user)
        return :unauthorized
      end

      if check_quota
        indexed = CopilotIndexedRepositories.where(organization_id: owner.id, markdown_only: false).count
        available = CopilotIndexedRepositories::DEFAULT_COPILOT_INDEXING_QUOTA
        if GitHub.flipper[:copilot_expanded_indexing_quota].enabled?(repo.owner)
          available *= 2
        end

        if indexed >= available
          return :quota_exhausted
        end
      end
    end

    :ok
  end

  def get_indexing_status(current_user, actor, repo, tenant)
    resp = Search::Blackbird::Client.get_repository(actor, repo.name_with_display_owner, tenant)

    maybe_err = resp.error
    data = if !maybe_err.nil? && maybe_err.code == :not_found
      # The repository is not indexed by blackbird (or not available to
      # this user) but shouldn't fail here, since we could still potentially
      # index it
      return {
        code_status: "not_indexed",
        docs_status: "not_indexed",
      }
    elsif resp.error
      return nil
    else
      resp.data.to_h
    end

    docs_status = "not_indexed"
    code_status = "not_indexed"
    data[:snapshot_entries].each do |entry|
      if entry[:experiments].key?(Search::Blackbird::ENABLE_DOCS_EMBEDDING_EXPERIMENT)
        docs_status = "indexing"

        if entry[:serving_offset] > 0 && entry[:serving_offset] < data[:serving_corpus][:serving_offset]
          docs_status = "indexed"
          break
        end
      end
    end

    data[:snapshot_entries].each do |entry|
      if entry[:experiments].key?(Search::Blackbird::ENABLE_CODE_EMBEDDING_EXPERIMENT)
        code_status = "indexing"

        if docs_status == "not_indexed"
          docs_status = "indexing"
        end

        if entry[:serving_offset] > 0 && entry[:serving_offset] < data[:serving_corpus][:serving_offset]
          code_status = "indexed"
          docs_status = "indexed"
          break
        end
      end
    end

    # Blackbird may take a few minutes to recognize a recently index repository
    # as indexing yet, so as a backup we should check the CopilotIndexedRepositories
    # table to see if it has been queued.
    if code_status == "not_indexed" || docs_status == "not_indexed"
      cir = CopilotIndexedRepositories.find_by(repository_id: repo.id)
      if !cir.nil?
        if cir.markdown_only
          if docs_status == "not_indexed"
            docs_status = "indexing"
          end
        else
          if docs_status == "not_indexed"
            docs_status = "indexing"
          end

          if code_status == "not_indexed"
            code_status = "indexing"
          end
        end
      end
    end

    if code_status == "not_indexed" || docs_status == "not_indexed"
      # Log if we're saying `not_indexed` for a repo that should definitely be indexed
      # https://github.com/github/copilot-core-productivity/issues/1698#issuecomment-2127770879
      if repo.feature_enabled?(:log_if_blackbird_repo_not_indexed)
        GitHub.logger.error(
          "Indexed repo marked as not_indexed",
          "gh.blackbird.embeddings.docs_status" => docs_status,
          "gh.blackbird.embeddings.code_status" => code_status,
          "gh.blackbird.get_repository.data" => data.to_json,
          "gh.repo.name_with_owner" => repo.name_with_display_owner,
          "gh.user.login" => current_user.display_login,
        )
      end
    end

    {
      docs_status: docs_status,
      code_status: code_status,
    }
  end
end
