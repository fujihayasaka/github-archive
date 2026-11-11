# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("repository.create") do |payload|
    repository = payload[:repository]

    serialized_actor = serializer.user(payload[:actor])
    gh_request_context = GitHub.context
    serialized_request_context = serializer.request_context(gh_request_context)
    serialized_repository = serializer.repository(payload[:repository])
    if payload[:parent].present?
      overrides_hash = {
        parent_owner_id: payload[:parent].owner_id,
      }.tap do |hash|
        hash[:parent_owner_type] = payload[:parent].owner_type
      end
      serialized_repository = serializer.repository(
        payload[:repository],
        overrides: overrides_hash,
      )
    end

    message = {
      actor: serialized_actor,
      request_context: serialized_request_context,
      repository: serialized_repository,
      gitignore_template: payload[:gitignore_template],
      license_template: payload[:license_template],
      init_with_readme: payload[:init_with_readme],
      owner: serializer.user(payload[:owner]),
    }

    publish(message, schema: "github.v1.RepositoryCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: nil,
      action_type: :CREATE,
      content_type: :REPOSITORY_DESCRIPTION,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.RepositoryCreate"),
      content_database_id: serialized_repository[:id],
      content_global_relay_id: serialized_repository[:global_relay_id],
      content_created_at: serialized_repository[:created_at],
      content_updated_at: serialized_repository[:updated_at],
      title: serializer.specimen_data(repository.name),
      content: serializer.specimen_data(repository.description),
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: serializer.repository_owner(repository),
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(repository),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.visibility_changed") do |payload|
    message = {
      name_with_owner: payload[:name_with_owner],
      repository_id: payload[:repository_id],
      is_private: payload[:is_private],
      is_fork: payload[:is_fork],
      visibility: payload[:visibility],
      feature_flags: payload[:feature_flags],
    }
    publish(message, schema: "github.v1.RepositoryVisibilityChanged", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.archived_status_changed") do |payload|
    message = {
      repository_id: payload[:repository_id],
      repository_global_id: payload[:repository_global_id],
      is_archived: payload[:is_archived],
    }
    publish(message, schema: "github.v1.RepositoryArchivedStatusChanged", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.rename") do |payload|
    gh_request_context = GitHub.context

    message = {
      request_context: serializer.request_context(gh_request_context),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      previous_name: payload[:previous_name],
      current_name: payload[:current_name],
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
    }

    publish(message, schema: "github.v1.RepositoryRename", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.aleph_reindex") do |payload|
    gh_request_context = GitHub.context

    message = {
      actor: serializer.user(payload[:actor]),
      owner: serializer.user(payload[:owner]),
      request_context: serializer.request_context(gh_request_context),
      repository: serializer.repository(payload[:repository]),
      after: payload[:after],
      ref: payload[:ref]&.dup&.force_encoding(Encoding::UTF_8),
      feature_flags: payload[:feature_flags],
    }

    publish(message,
      topic: "github.v0.AlephdIndexRepository",
      schema: "github.v1.RepositoryPush",
      partition_key: message[:repository][:id], topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }, # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    )
  end

  subscribe("repository.post_receive_commits") do |payload|
    commits = payload[:commits]
    serialized_users = Hash.new { |hash, user| hash[user] = serializer.user(user) }

    messages = begin
      commits.map do |commit|
        co_authors = commit.author_names.drop(1).zip(commit.author_emails.drop(1)).filter_map do |name, email|
          next if name.blank? || email.blank?
          { email: email, name: name }
        end

        {
          authored_at: commit.authored_date,
          committed_at: commit.committed_date,
          oid: commit.oid,
          author: {
            email: commit.author_email,
            name: commit.author_name,
            user: serialized_users[commit.author],
          },
          co_authors: co_authors,
          repository: serializer.repository(commit.repository),
          repository_owner: serializer.repository_owner(commit.repository.owner),
          diff_stats: serializer.commit_diff_stats(commit.diff_stats),
        }
      end
    rescue GitRPC::InvalidRepository
      # The repo disappeared (was deleted) immediately after being pushed to,
      # or created. Don't report partial data for the push.
      []
    end

    messages.each do |message|
      publish(
        message,
        schema: "github.v1.PostReceiveCommit",
        partition_key: message.fetch(:repository).fetch(:id), topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }, # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
      )
    end
  end

  subscribe("repository.deleted") do |payload|
    deleted_repository = payload[:deleted_repository]
    deleted_repo_next_global_id = deleted_repository&.global_relay_id
    unless GitHub.enterprise?
      begin
        deleted_repo_next_global_id = deleted_repository&.next_global_id
      rescue ArgumentError
        deleted_repo_next_global_id = ""
      end
    end

    message = {
      actor: serializer.user(payload[:actor]),
      deleted_repository: serializer.repository(deleted_repository, overrides: { next_global_id: deleted_repo_next_global_id }),
    }

    publish(message, schema: "github.v1.RepositoryDeleted", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.restored") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      restored_repository: serializer.repository(payload[:restored_repository]),
    }

    publish(message, schema: "github.v1.RepositoryRestored", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.invite") do |payload|
    gh_request_context = GitHub.context

    message = {
      actor: serializer.user(payload[:actor]),
      invitee: serializer.user(payload[:invitee]),
      request_context: serializer.request_context(gh_request_context),
      repository: serializer.repository(payload[:repository]),
    }

    publish(message, schema: "github.v1.RepositoryInvite", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.push_vulnerability_notification") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
    }

    publish(message, schema: "github.v1.RepositoryPushVulnerabilityNotification", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.commit_status") do |payload|
    status = payload[:status]

    message = {
      database_id: status.id,
      context: status.context,
      commit_sha: status.sha,
      state: status.state.upcase,
      repository_id: status.repository_id,
      branch_names: status.all_or_dependabot_branches.map { |name| name.dup.force_encoding("UTF-8") },
    }

    publish(message, schema: "github.v1.RepositoryCommitStatusCreated", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.repository.click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:client][:user]),
      target: payload[:target],
    }
    if payload[:repository_id]
      repo = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
        Repositories.domain.by_id(payload[:repository_id])
      else
        Repository.find_by(id: payload[:repository_id])
      end
      message[:repository] = serializer.repository(repo) if repo
      message[:owner] = serializer.user(repo.owner) if repo&.owner
    end
    publish(message, schema: "github.v1.RepositoryClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.clone_or_download.click") do |payload|
    repo = if payload[:repository_id]
      if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
        Repositories.domain.by_id(payload[:repository_id])
      else
        Repository.find_by(id: payload[:repository_id])
      end
    end
    gist = if payload[:gist_id]
      Gist.find_by(id: payload[:gist_id])
    end
    owner = if repo && repo.owner
      serializer.user(repo.owner)
    elsif gist && gist.owner
      serializer.user(gist.owner)
    end
    message = {
      actor: serializer.user(payload[:client][:user]),
      feature_clicked: payload[:feature_clicked],
      owner: owner,
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      git_repository_type: payload[:git_repository_type],
    }
    message[:repository] = serializer.repository(repo) if repo
    message[:gist] = serializer.gist(gist) if gist
    publish(message, schema: "github.v1.CloneDownloadClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("key_link.create") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repo]),
      repository_owner: serializer.user(payload[:repo].owner),
      prefix: payload[:key_prefix],
      template: payload[:url_template],
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamuri_form_signals]),
    }

    publish(message, schema: "github.v1.KeyLinkCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.repository_create.click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:client][:user]),
      target: payload[:event_target],
    }

    publish(message, schema: "github.v1.RepositoryCreateClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.repository-hovercard-hover") do |payload|
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repositoryId])
    else
      Repository.find_by(id: payload[:repositoryId])
    end

    message = {
      actor: serializer.user(payload[:client][:user]),
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      repository: serializer.repository(repo),
      context: serializer.hovercard_context_string(payload[:subject]),
    }

    publish(message, schema: "github.v1.RepositoryHovercardHover", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.commit-hovercard-hover") do |payload|
    commit_id = payload[:commitGlobalRelayId]&.to_s
    decoded_commit_id = nil
    commit = if commit_id
      if Platform::Helpers::GlobalId.next?(commit_id)
        parsed_id = Platform::Helpers::GlobalId.parse(commit_id)
        Platform::Security::RepositoryAccess.with_viewer(payload[:actor]) do
          Platform::Objects::Commit.load_from_next_global_id(parsed_id).sync
        end
      else
        decoded_commit_id = Platform::Helpers::NodeIdentification.from_global_id(commit_id).last
        Platform::Security::RepositoryAccess.with_viewer(payload[:actor]) do
          Platform::Objects::Commit.load_from_global_id(decoded_commit_id).sync
        end
      end
    end

    message = {
      actor: serializer.user(payload[:client][:user]),
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      commit: serializer.commit(commit),
      context: serializer.hovercard_context_string(payload[:subject]),
    }

    publish(message, schema: "github.v1.CommitHovercardHover", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.repository_empty_state.click") do |payload|
    gh_request_context = GitHub.context

    message = {
      request_context: serializer.request_context(gh_request_context),
      actor: serializer.user(payload[:client][:user]),
      target: payload[:event_target],
      repository_context: payload[:repository_context],
    }

    publish(message, schema: "github.v1.RepositoryEmptyStateClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.repository_toc_menu.click") do |payload|
    repository = Repositories.domain.by_id(payload[:repository_id].to_i)

    gh_request_context = GitHub.context

    message = {
      request_context: serializer.request_context(gh_request_context),
      actor: serializer.user(payload[:client][:user]),
      repository: serializer.repository(repository),
      target: payload[:target],
    }

    publish(message, schema: "github.v1.RepositoryTocMenuClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.missing_branch_redirect") do |payload|
    repo = payload[:repository]

    gh_request_context = GitHub.context

    message = {
      actor: serializer.user(payload[:actor]),
      request_context: serializer.request_context(gh_request_context),
      repository: serializer.repository(repo),
      repository_owner: serializer.repository_owner(repo.owner),
      missing_branch_was_master: payload[:missing_branch_was_master],
    }

    publish(message.freeze, schema: "github.repositories.v1.MissingBranchRedirect",
      publisher: GitHub.low_latency_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.rename_branch") do |payload|
    repo = payload[:repository]

    message = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(repo),
      repository_owner: serializer.repository_owner(repo.owner),
      old_branch: serializer.force_utf8(payload[:old_branch]),
      new_branch: serializer.force_utf8(payload[:new_branch]),
      default_branch: payload[:default_branch],
    }.freeze

    publish(message, schema: "github.repositories.v1.RenameBranch",
      publisher: GitHub.low_latency_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.issue_template_update") do |payload|
    repo = payload[:repository]

    gh_request_context = GitHub.context

    message = {
      actor: serializer.user(payload[:actor]),
      owner: serializer.user(repo.owner),
      repository: serializer.repository(repo),
      filename: payload[:filename],
      sha: payload[:sha],
      messages: payload[:messages],
      request_context: serializer.request_context(gh_request_context),
    }.freeze

    publish(message, schema: "github.issue_templates.v0.TemplateUpdateError",
            publisher: GitHub.low_latency_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.internal_clone_complete") do |payload|
    source_repository = payload[:source_repository]
    destination_repository = payload[:destination_repository]

    message = {
      source_repository: serializer.repository(source_repository),
      destination_repository: serializer.repository(destination_repository)
    }.freeze

    publish(message, schema: "github.repositories.v1.InternalCloneComplete",
            publisher: GitHub.low_latency_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository.bulk.invite") do |payload|
    message = {
     actor: serializer.user(payload[:actor]),
     repository: serializer.repository(payload[:repository]),
     successful_user_invites: payload[:successful_user_invites],
     successful_email_invites: payload[:successful_email_invites],
     failed_user_invites: payload[:failed_user_invites],
     failed_email_invites: payload[:failed_email_invites],
     organization: serializer.organization(payload[:organization]),
   }

    publish(message, schema: "github.v1.RepositoryBulkInvite")
  end

  subscribe("repository.import_completed") do |payload|
    message = {
      repository: serializer.repository(payload[:repository]),
      actor: serializer.user(payload[:actor]),
      final_status: serializer.enum_from_string(payload[:completed_status]),
    }

    publish(message, schema: "github.repositories.v2.Imported")
  end

  subscribe("repository.transfer_email") do |payload|
    message = {
      repository: serializer.repository(payload[:repository]),
      email_reason: serializer.enum_from_string(payload[:email_reason]),
      user: serializer.user(payload[:user]),
      target_id: payload[:target_id],
    }

    publish(message, schema: "github.repositories.v1.TransferEmail")
  end

  subscribe("repo.add_member") do |payload|
    repository = payload[:repo]
    message = {
      actor: serializer.user(payload[:actor]),
      member: serializer.user(payload[:user]),
      repository: {
          id: repository.id,
          name: repository.name,
          visibility: repository.visibility,
          parent_id: repository.parent_id,
          stargazer_count: [repository.stargazer_count, 0].max,
          organization_id: repository.organization_id,
          owner_id: repository.owner_id,
      },
      repository_owner_customer_id: Licensing::Customer.id_for(repository),
      is_repository_advisory_workspace: repository.advisory_workspace?,
    }

    publish(message, schema: "github.v1.RepositoryAddMember")
  end

  subscribe("repository.details_updated") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      description: payload[:description],
      homepage: payload[:homepage],
    }

    publish(message, schema: "github.repositories.v1.RepositoryDetailsUpdated")
  end

  subscribe("repository.remove_content_warning") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
    }

    publish(message, schema: "github.v1.RemoveContentWarning")
  end

  subscribe("repository.enabled") do |payload|
    message = {
      repository: serializer.repository(payload[:repository]),
      actor: serializer.user(payload[:actor]),
      enabled_at: payload[:enabled_at].try(:to_i),
    }

    publish(message, schema: "github.v1.RepositoryEnabled")
  end

  subscribe("repository.country_unblocked") do |payload|
    message = {
      repository: serializer.repository(payload[:repository]),
      actor: serializer.user(payload[:actor]),
      unblocked_at: payload[:unblocked_at].try(:to_i),
      type: payload[:type].upcase.to_sym,
      country_codes: payload[:country_codes],
      country_names: payload[:country_names],
    }

    publish(message, schema: "github.v1.RepositoryCountryUnblocked")
  end

  subscribe(/repository_secret\.(create|remove)/) do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      repository: serializer.repository(payload[:owner]),
      actor: serializer.user(payload[:actor]),
      name: payload[:name],
      state: payload[:state],
    }

    publish(message, schema: "github.v1.RepositorySecretChanged", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository_image.created") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      uploader: serializer.user(payload[:uploader]),
      repository_image: serializer.repository_image(payload[:repository_image]),
      repository: serializer.repository(payload[:repository]),
    }

    publish(message, schema: "github.v1.RepositoryImageCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository_image.deleted") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      destroyed_repository_image: serializer.repository_image(payload[:repository_image]),
    }

    publish(message, schema: "github.v1.RepositoryImageDestroy", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("repository_clone.created") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      clone_repository: serializer.repository(payload[:clone_repository]),
      template_repository: serializer.repository(payload[:template_repository]),
    }

    publish(message, schema: "github.v1.RepositoryCloneCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
