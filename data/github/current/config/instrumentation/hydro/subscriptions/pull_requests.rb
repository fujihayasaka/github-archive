# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to Pull Requests.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("pull_request.add_to_stack") do |payload|
    pull = payload[:pull_request]
    next unless pull.present?

    stack = payload[:stack] || pull.stack
    next unless stack.present?

    issue = payload[:issue] || pull.issue
    repository = payload[:repository] || pull.base_repository

    actor = payload[:actor]
    serialized_actor = \
      if actor
        {
          id: actor.id,
          global_relay_id: actor.global_relay_id,
          login: actor.login,
          type: UserEntitySerializer::USER_TYPES.fetch(actor.class.name, :UNKNOWN),
        }
      else
        nil
      end

    # Message payload only includes data used by turboscan pull request event processor.
    # We're intentionally not using entity serializers in order to reduce db queries and gitrpc calls.
    message = {
      actor: serialized_actor,
      issue: {
        id_value: issue.id,
        global_relay_id: issue.global_relay_id,
        number: issue.number,
      },
      pull_request: {
        id: pull.id,
        global_relay_id: pull.global_relay_id,
        head_branch: pull.head_ref_name,
        base_branch: pull.base_ref_name,
        head_sha: pull.head_sha,
        base_sha: pull.base_sha,
        updated_at: pull.updated_at,
      },
      repository: {
        id: repository.id,
        global_relay_id: repository.global_relay_id,
        name: repository.name,
        visibility: repository.visibility,
        default_branch: repository.default_branch&.dup&.force_encoding(Encoding::UTF_8)&.scrub!,
        owner_id: repository.owner_id,
      },
      stack: {
        id: stack.id,
        base_branch: stack.base_ref,
        base_sha: stack.base_sha,
      },
    }

    if FeatureFlag.vexi.enabled?(:hydro_pull_request_initiator_id, repository, default: false)
      attribution_user_id = pull.audit_log_copilot_attribution_user_id
      message[:pull_request][:initiator_id] = attribution_user_id if attribution_user_id
    end

    publish(message, schema: "github.v1.PullRequestAddToStack")
  end

  subscribe("pull_request.create") do |payload|
    pull = payload[:pull_request]
    next unless pull.present?

    initiating_user = payload[:initiator]
    actor = pull.user
    repository = pull.repository

    GitHub::PrefillAssociations.prefill_associations(pull, [{ repository: [:owner, :primary_language] }, { head_repository: [:owner, :primary_language] }, :issue, :stack], available_records: [repository])

    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_actor = serializer.user(actor)
    serialized_repository = serializer.repository(repository)
    serialized_repository_owner = serializer.user(repository.owner)
    serialized_issue = serializer.issue(pull.issue)
    serialized_issue_creator = serializer.user(payload[:issue_creator])
    serialized_changed_files = pull.changed_files_for_instrumentation.map { |file| serializer.changed_file(file, overrides: { change_type: file.change_type_symbol }) }

    pull_request_overrides = build_pull_request_overrides_with_diff_stats(pull, { changed_files: serialized_changed_files })
    serialized_pull_request = serializer.pull_request(pull, overrides: pull_request_overrides)

    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_specimen_title = serializer.specimen_data(pull.title)
    serialized_specimen_body = serializer.specimen_data(pull.body)
    serialized_head_repository = serializer.repository(pull.head_repository)

    hydro_payload = {
      pull_request: serialized_pull_request,
      issue: serialized_issue,
      actor: serialized_actor,
      actor_profile_location: actor&.profile_location,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      title: pull.title,
      body: pull.body,
      head_repository: serialized_head_repository,
      feature_flags: pull.head_repository.pull_request_create_feature_flags,
      blob_languages: pull.all_languages_in_diff,
    }

    if initiating_user.present?
      serialized_initiator = serializer.user(initiating_user)
      hydro_payload[:initiator] = serialized_initiator
    end

    serialized_stack = serializer.pull_request_stack(pull.stack)
    if serialized_stack.present?
      hydro_payload[:stack] = serialized_stack
    end

    publish(hydro_payload, partition_key: hydro_payload[:repository][:id], schema: "github.v1.PullRequestCreate", publisher: GitHub.legacy_user_generated_content_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      action_type: :CREATE,
      content_type: :PULL_REQUEST,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.PullRequestCreate"),
      content_database_id: serialized_pull_request[:id],
      content_global_relay_id: serialized_pull_request[:global_relay_id],
      content_created_at: serialized_pull_request[:created_at],
      content_updated_at: serialized_pull_request[:updated_at],
      title: serialized_specimen_title,
      content: serialized_specimen_body,
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: serialized_repository_owner,
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(pull),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish_secret_scanning_pr_scan(pull, serialized_repository, serialized_repository_owner, serialized_actor)
  end

  # Technically PullRequest updates are also Issue updates when the title or body is changed.
  # Here we subscribe to issue.update which gets published by Issue#instrument_hydro_update_event
  # which is called in each API we expose to end users including the v3 API, the GraphQL API,
  # and the IssuesController which is used by the PullRequest edit form on the website.
  subscribe("issue.update") do |payload|
    pull = payload[:issue].pull_request

    next unless pull.present?

    actor = pull.user
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_actor = serializer.user(payload[:actor])
    serialized_repository = serializer.repository(pull.repository)
    serialized_repository_owner = serializer.user(pull.repository.owner)
    serialized_pull_request = serializer.pull_request(pull)
    serialized_issue = serializer.issue(pull.issue)
    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_specimen_title = serializer.specimen_data(pull.title)
    serialized_specimen_body = serializer.specimen_data(pull.body)

    hydro_payload = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      pull_request: serialized_pull_request,
      issue: serialized_issue,
      previous_title: payload[:previous_title],
      current_title: payload[:current_title],
      previous_body: payload[:previous_body],
      current_body: payload[:current_body],
      feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(pull.repository).pull_request_scanning_service_flags,
    }

    publish(hydro_payload, schema: "github.v1.PullRequestUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      action_type: :UPDATE,
      content_type: :PULL_REQUEST,
      actor: serialized_actor,
      original_type_url: nil, # there is no original_type_url for PullRequest update right now
      content_database_id: serialized_pull_request[:id],
      content_global_relay_id: serialized_pull_request[:global_relay_id],
      content_created_at: serialized_pull_request[:created_at],
      content_updated_at: serialized_pull_request[:updated_at],
      title: serialized_specimen_title,
      content: serialized_specimen_body,
      parent_content_author: nil,
      parent_content_database_id: nil,
      parent_content_global_relay_id: nil,
      parent_content_created_at: nil,
      parent_content_updated_at: nil,
      owner: serialized_repository_owner,
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(pull),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish_secret_scanning_pr_scan(pull, serialized_repository, serialized_repository_owner, serialized_actor)
  end

  subscribe("issue_comment.create") do |payload|
    pull = payload[:issue].pull_request

    next unless pull.present?

    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_actor = serializer.user(payload[:actor])
    serialized_repository = serializer.repository(pull.repository)
    serialized_repository_owner = serializer.user(pull.repository.owner)
    serialized_pull_request = serializer.pull_request(pull)
    serialized_issue = serializer.issue(payload[:issue])
    serialized_issue_comment = serializer.issue_comment(payload[:issue_comment])

    hydro_payload = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      issue: serialized_issue,
      issue_comment: serialized_issue_comment,
      body: payload[:issue_comment].body,
      feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(pull.repository).pull_request_scanning_service_flags,
    }

    if payload[:actor]&.feature_flag_enabled?(:copilot_swe_agent_url_trigger, default: false)
      hydro_payload[:event_url] = serializer.url_for_model(payload[:issue_comment])
    end

    # Prefer the persisted attribution on the comment (set at write time when
    # created via a GitHub App), and fall back to the request-scoped context for
    # paths where the column isn't populated.
    if (github_app_id = payload[:issue_comment].performed_by_integration_id || GitHub.context[:integration_id])
      hydro_payload[:github_app_id] = github_app_id
    end

    publish(hydro_payload, schema: "github.v1.PullRequestTimelineCommentCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })

    publish_secret_scanning_pr_comment_scan(payload[:issue_comment], serialized_repository, serialized_repository_owner, serialized_actor)
  end

  subscribe("issue_comment.update") do |payload|
    pull = payload[:issue].pull_request

    next unless pull.present?

    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_actor = serializer.user(payload[:actor])
    serialized_repository = serializer.repository(pull.repository)
    serialized_repository_owner = serializer.user(pull.repository.owner)
    serialized_pull_request = serializer.pull_request(pull)
    serialized_issue = serializer.issue(payload[:issue])
    serialized_issue_comment = serializer.issue_comment(payload[:issue_comment])

    hydro_payload = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      issue: serialized_issue,
      issue_comment: serialized_issue_comment,
      previous_body: serializer.force_utf8(payload[:previous_body]),
      current_body: serializer.force_utf8(payload[:issue_comment].body),
      feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(pull.repository).pull_request_scanning_service_flags,
    }

    publish(hydro_payload, schema: "github.v1.PullRequestTimelineCommentUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 })

    publish_secret_scanning_pr_comment_scan(payload[:issue_comment], serialized_repository, serialized_repository_owner, serialized_actor)
  end

  subscribe(/browser.rerequest_review\.(sidebar|mergebox)/) do |payload|
    actor = User.find_by(id: payload[:actor_id])
    if FeatureFlag.vexi.enabled?(:skip_rerequest_review_event, actor, default: false)
      next
    end

    subject = User.find_by(id: payload[:subject_id])
    pull = PullRequest.find_by(id: payload[:pull_request_id])

    next unless pull.present?

    message = {
      pull_request: serializer.pull_request(pull),
      actor: serializer.user(actor),
      subject_user: serializer.user(subject),
      repository: serializer.repository(pull.repository),
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      action: serializer.enum_from_string(payload[:action]),
      as_code_owner: false,
    }

    publish(message, schema: "github.v1.PullRequestReviewRequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe(/pull_request_review_request\.(create|remove)/) do |payload|
    actor = payload[:actor]
    subject_user = payload[:subject_type] == "User" ? serializer.user(payload[:subject_user]) : nil

    # Use centralized helper to determine team reviewer types
    pull = payload[:pull_request]
    org = pull&.repository&.owner
    team_reviewer_types = org.is_a?(Organization) ? org.team_reviewer_types : ["Team"]

    subject_team = payload[:subject_type].in?(team_reviewer_types) ? serializer.team(payload[:subject_user]) : nil
    as_code_owner = payload[:as_code_owner]
    automatic_copilot_review = payload[:automatic_copilot_review]
    automatic_copilot_reason = payload[:automatic_copilot_reason]

    next unless pull.present?

    message = {
      pull_request: serializer.pull_request(pull),
      actor: serializer.user(actor),
      subject_user: subject_user,
      subject_team: subject_team,
      repository: serializer.repository(pull.repository),
      request_context: serializer.request_context(GitHub.context.to_hash),
      action: serializer.enum_from_string(payload[:action]),
      as_code_owner: as_code_owner,
      automatic_copilot_review: automatic_copilot_review,
      automatic_copilot_reason: automatic_copilot_reason,
    }

    publish(message, schema: "github.v1.PullRequestReviewRequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.close") do |payload|
    pull = payload[:pull_request]
    actor = payload[:actor]

    next unless pull.present?

    hydro_payload = {
      pull_request: serializer.pull_request(pull),
      issue: serializer.issue(pull.issue),
      repository: serializer.repository(pull.repository),
      repository_owner: serializer.user(pull.repository.owner),
    }

    if actor.present?
      hydro_payload[:actor] = serializer.user(actor)
    end

    publish(hydro_payload, schema: "github.v1.PullRequestClose", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.merge") do |payload|
    pull = payload[:pull_request]
    actor = payload[:actor]
    author = payload[:author]

    next unless pull.present?

    author_has_write_access = pull.author_association.member? ||
                              pull.author_association.collaborator? ||
                              pull.author_association.owner?

    serialized_changed_files = pull.changed_files_for_instrumentation.map { |file| serializer.changed_file(file, overrides: { change_type: file.change_type_symbol }) }

    pull_request_overrides = build_pull_request_overrides_with_diff_stats(pull, { changed_files: serialized_changed_files })

    hydro_payload = {
      pull_request: serializer.pull_request(pull, overrides: pull_request_overrides),
      issue: serializer.issue(pull.issue),
      repository: serializer.repository(pull.repository),
      repository_owner: serializer.user(pull.repository.owner),
      protected_branch: serializer.protected_branch(payload[:protected_branch]),
      merge_action: payload[:merge_action],
      merge_method: payload[:merge_method],
      merge_state_status: payload[:merge_state_status],
      pr_approved: pull.reviews.map(&:state).include?(PullRequestReview.state_value(:approved)),
      actor_has_write_access: author_has_write_access,
      merge_commit_title: payload[:merge_commit_title],
      merge_commit_message: payload[:merge_commit_message]&.truncate(PullRequest::AnalyticsDependency::HYDRO_MAX_MERGE_COMMIT_MESSAGE_LENGTH),
      default_merge_commit_message_and_title: payload[:default_merge_commit_message_and_title],
      merge_commit_sha: payload[:merge_commit_sha],
    }

    if pull.repository.owner&.feature_flag_enabled?(:pr_reviewed_by_copilot_code_review_in_pr_merge, default: false)
      hydro_payload[:pr_reviewed_by_copilot_code_review] = pull.reviews.submitted.copilot.exists?
    end

    if actor
      hydro_payload[:actor] = serializer.user(actor)
      hydro_payload[:actor_profile_location] = actor.profile_location
    end

    if author
      hydro_payload[:author] = serializer.user(author)
    end

    opener = pull.user
    if opener
      hydro_payload[:opener_login] = opener.login
      hydro_payload[:opener_profile_location] = opener.profile_location
    end

    publish(hydro_payload, schema: "github.v1.PullRequestMerge", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.in_progress") do |payload|
    pull = payload[:pull_request]
    actor = payload[:actor]

    next unless pull.present?

    hydro_payload = {
      pull_request: serializer.pull_request(pull),
      issue: serializer.issue(pull.issue),
      repository: serializer.repository(pull.repository),
      repository_owner: serializer.user(pull.repository.owner),
      reviewable_state_was: payload[:reviewable_state_was],
    }

    if actor.present?
      hydro_payload[:actor] = serializer.user(actor)
    end

    publish(hydro_payload, schema: "github.v1.PullRequestInProgress", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.synchronize") do |payload|
    pull = payload[:pull_request]
    next unless pull.present?

    issue = payload[:issue]
    actor = payload[:actor]
    repository = payload[:repository]

    GitHub::PrefillAssociations.prefill_associations(pull, :stack)
    if repository
      GitHub::PrefillAssociations.prefill_associations(pull, [:base_repository, :repository], available_records: [repository])
    end

    pull_request_overrides = build_pull_request_overrides_with_diff_stats(pull)

    hydro_payload = {
      repository: serializer.repository(repository),
      base_repository: serializer.repository(pull.base_repository),
      pull_request: serializer.pull_request(pull, overrides: pull_request_overrides),
      issue: serializer.issue(issue),
      protected_branch: serializer.protected_branch(payload[:protected_branch]),
      ref: payload[:ref],
      before_oid: payload[:before],
      after_oid: payload[:after],
    }

    if actor
      hydro_payload[:actor] = serializer.user(actor)
    end

    serialized_stack = serializer.pull_request_stack(pull.stack)
    if serialized_stack.present?
      hydro_payload[:stack] = serialized_stack
    end

    publish(hydro_payload, schema: "github.v1.PullRequestSynchronize")
  end

  subscribe("pull_request.change_base") do |payload|
    pull = payload[:pull_request]
    next unless pull.present?

    actor = payload[:actor]
    issue = payload[:issue]
    repository = payload[:repository]

    GitHub::PrefillAssociations.prefill_associations(pull, :stack)
    if repository
      GitHub::PrefillAssociations.prefill_associations(pull, [:base_repository, :repository], available_records: [repository])
    end

    pull_request_overrides = build_pull_request_overrides_with_diff_stats(pull)

    hydro_payload = {
      repository: serializer.repository(repository),
      base_repository: serializer.repository(pull.base_repository),
      pull_request: serializer.pull_request(pull, overrides: pull_request_overrides),
      issue: serializer.issue(issue),
      protected_branch: serializer.protected_branch(payload[:protected_branch]),
      before_base_ref: payload[:before_base_ref],
      before_base_sha: payload[:before_base_sha],
      after_base_ref: payload[:after_base_ref],
      after_base_sha: payload[:after_base_sha],
    }

    if actor
      hydro_payload[:actor] = serializer.user(actor)
    end

    # We currently do not allow changing the base branch of a stacked pull request. See PullRequest#can_change_base_branch!
    # This may change in the future, so we include stack data in the hydro event for future-proofing, because it's
    # required for triggering code scanning and code quality runs correctly on stacked pull requests.
    serialized_stack = serializer.pull_request_stack(pull.stack)
    if serialized_stack.present?
      hydro_payload[:stack] = serialized_stack
    end

    publish(hydro_payload, schema: "github.v1.PullRequestChangeBase")
  end

  subscribe("pull_request.ready_for_review") do |payload|
    pull = payload[:pull_request]
    actor = payload[:actor]

    next unless pull.present?

    hydro_payload = {
      pull_request: serializer.pull_request(pull),
      issue: serializer.issue(pull.issue),
      repository: serializer.repository(pull.repository),
      repository_owner: serializer.user(pull.repository.owner),
      reviewable_state_was: payload[:reviewable_state_was],
    }

    if actor.present?
      hydro_payload[:actor] = serializer.user(actor)
    end

    publish(hydro_payload, schema: "github.v1.PullRequestReadyForReview", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.converted_to_draft") do |payload|
    pull = payload[:pull_request]
    actor = payload[:actor]

    next unless pull.present?

    hydro_payload = {
      pull_request: serializer.pull_request(pull),
      issue: serializer.issue(pull.issue),
      repository: serializer.repository(pull.repository),
      repository_owner: serializer.user(pull.repository.owner),
      reviewable_state_was: payload[:reviewable_state_was],
    }

    if actor.present?
      hydro_payload[:actor] = serializer.user(actor)
    end

    publish(hydro_payload, schema: "github.v1.PullRequestConvertToDraft", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.reopen") do |payload|
    pull = payload[:pull_request]
    actor = payload[:actor]

    next unless pull.present?

    hydro_payload = {
      pull_request: serializer.pull_request(pull),
      issue: serializer.issue(pull.issue),
      repository: serializer.repository(pull.repository),
      repository_owner: serializer.user(pull.repository.owner),
    }

    if actor.present?
      hydro_payload[:actor] = serializer.user(actor)
    end

    publish(hydro_payload, schema: "github.v1.PullRequestReopen", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.auto_merge_enable") do |payload|
    hydro_payload = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      pull_request: serializer.pull_request(payload[:pull_request]),
      protected_branch: serializer.protected_branch(payload[:protected_branch]),
      unfulfilled_protected_branch_policy_reason_codes: payload[:unfulfilled_protected_branch_policy_reason_codes],
      auto_merge_request: serializer.auto_merge_request(payload[:auto_merge_request])
    }
    publish(hydro_payload, schema: "github.v1.PullRequestAutoMergeEnable", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.auto_merge_disable") do |payload|
    hydro_payload = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      pull_request: serializer.pull_request(payload[:pull_request]),
      disabled_message: payload[:disabled_message],
      protected_branch: serializer.protected_branch(payload[:protected_branch]),
      unfulfilled_protected_branch_policy_reason_codes: payload[:unfulfilled_protected_branch_policy_reason_codes],
      auto_merge_request: serializer.auto_merge_request(payload[:auto_merge_request])
    }
    publish(hydro_payload, schema: "github.v1.PullRequestAutoMergeDisable", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe(/pull_request_file\.(viewed|unviewed|dismissed)/) do |payload|
    message = {
      pull_request: serializer.pull_request(payload[:pull_request]),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      file_path: serializer.force_utf8(payload[:file_path]),
      request_context: serializer.request_context(GitHub.context.to_hash),
      action: serializer.enum_from_string(payload[:action]),
    }

    publish(message, schema: "github.v1.MarkFileAsViewed", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request_review_comment.create") do |payload|
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_actor = serializer.user(payload[:actor])
    serialized_repository = serializer.repository(payload[:repository])
    serialized_repository_owner = serializer.user(payload[:repository_owner])
    serialized_pull_request = serializer.pull_request(payload[:pull_request])
    serialized_pull_request_creator = serializer.user(payload[:pull_request_creator])
    serialized_pull_request_review_comment = serializer.pull_request_review_comment(payload[:review_comment])
    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_specimen_body = serializer.specimen_data(payload[:review_comment].body)

    message = {
      request_context: serialized_request_context,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      pull_request: serialized_pull_request,
      pull_request_review_comment: serialized_pull_request_review_comment,
      issue: serializer.issue(payload[:issue]),
      specimen_body: serialized_specimen_body,
      pull_request_review: serializer.pull_request_review(payload[:pull_request_review]),
      pull_request_review_thread: serializer.pull_request_review_thread(payload[:pull_request_review_thread]),
      feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(payload[:repository]).pull_request_scanning_service_flags,
    }

    publish(message, schema: "github.v1.PullRequestReviewCommentCreate", publisher: GitHub.legacy_user_generated_content_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      action_type: :CREATE,
      content_type: :PULL_REQUEST_REVIEW_COMMENT,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.PullRequestReviewCommentCreate"),
      content_database_id: serialized_pull_request_review_comment[:id],
      content_global_relay_id: serialized_pull_request_review_comment[:global_relay_id],
      content_created_at: serialized_pull_request_review_comment[:created_at],
      content_updated_at: serialized_pull_request_review_comment[:updated_at],
      title: nil,
      content: serialized_specimen_body,
      parent_content_author: serialized_pull_request_creator,
      parent_content_database_id: serialized_pull_request[:id],
      parent_content_global_relay_id: serialized_pull_request[:global_relay_id],
      parent_content_created_at: serialized_pull_request[:created_at],
      parent_content_updated_at: serialized_pull_request[:updated_at],
      owner: serialized_repository_owner,
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(payload[:review_comment]),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish_secret_scanning_pr_review_comment_scan(payload[:review_comment], serialized_repository, serialized_repository_owner, serialized_actor)
  end

  subscribe("pull_request_review_comment.update") do |payload|
    serialized_request_context = serializer.request_context(GitHub.context.to_hash)
    serialized_actor = serializer.user(payload[:actor])
    serialized_repository = serializer.repository(payload[:repository])
    serialized_repository_owner = serializer.user(payload[:repository_owner])
    serialized_pull_request = serializer.pull_request(payload[:pull_request])
    serialized_pull_request_creator = serializer.user(payload[:pull_request_creator])
    serialized_pull_request_review_comment = serializer.pull_request_review_comment(payload[:review_comment])
    serialized_spamurai_form_signals = serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals])
    serialized_specimen_body = serializer.specimen_data(payload[:review_comment].body)

    message = {
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      pull_request: serialized_pull_request,
      pull_request_review: serializer.pull_request_review(payload[:pull_request_review]),
      pull_request_review_comment: serialized_pull_request_review_comment,
      specimen_body: serialized_specimen_body,
      feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(payload[:repository]).pull_request_scanning_service_flags,
      issue: serializer.issue(payload[:issue]),
    }

    publish(message, schema: "github.v1.PullRequestReviewCommentUpdate", publisher: GitHub.legacy_user_generated_content_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    user_generated_content_msg = {
      request_context: serialized_request_context,
      spamurai_form_signals: serialized_spamurai_form_signals,
      action_type: :UPDATE,
      content_type: :PULL_REQUEST_REVIEW_COMMENT,
      actor: serialized_actor,
      original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.PullRequestReviewCommentUpdate"),
      content_database_id: serialized_pull_request_review_comment[:id],
      content_global_relay_id: serialized_pull_request_review_comment[:global_relay_id],
      content_created_at: serialized_pull_request_review_comment[:created_at],
      content_updated_at: serialized_pull_request_review_comment[:updated_at],
      title: nil,
      content: serialized_specimen_body,
      parent_content_author: serialized_pull_request_creator,
      parent_content_database_id: serialized_pull_request[:id],
      parent_content_global_relay_id: serialized_pull_request[:global_relay_id],
      parent_content_created_at: serialized_pull_request[:created_at],
      parent_content_updated_at: serialized_pull_request[:updated_at],
      owner: serialized_repository_owner,
      repository: serialized_repository,
      content_visibility: serialized_repository[:visibility],
      content_url: serializer.url_for_model(payload[:review_comment]),
    }

    publish(user_generated_content_msg, schema: "github.platform_health.v1.UserGeneratedContent", publisher: GitHub.user_generated_content_hydro_publisher, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish_secret_scanning_pr_review_comment_scan(payload[:review_comment], serialized_repository, serialized_repository_owner, serialized_actor)
  end

  subscribe("pull_request_review_comment.delete") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      pull_request: serializer.pull_request(payload[:pull_request]),
      pull_request_review: serializer.pull_request_review(payload[:pull_request_review]),
      pull_request_review_comment: serializer.pull_request_review_comment(payload[:review_comment]),
      pull_request_review_thread: serializer.pull_request_review_thread(payload[:pull_request_review_thread]),
    }

    publish(message, schema: "github.v1.PullRequestReviewCommentDelete", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request_review_thread.create") do |payload|
    message = {
      pull_request_review_thread: serializer.pull_request_review_thread(payload[:pull_request_review_thread]),
      repository: serializer.repository(payload[:repository]),
    }

    publish(message, schema: "github.v1.PullRequestReviewThreadCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request_review_thread.delete") do |payload|
    message = {
      pull_request_review_thread: serializer.pull_request_review_thread(payload[:pull_request_review_thread]),
      repository: serializer.repository(payload[:repository]),
    }

    publish(message, schema: "github.v1.PullRequestReviewThreadDelete", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request_review_thread.resolved") do |payload|
    message = {
      pull_request_review_thread: serializer.pull_request_review_thread(payload[:pull_request_review_thread]),
      repository: serializer.repository(payload[:pull_request_review_thread].repository),
      actor: serializer.user(payload[:actor]),
    }

    publish(
      message,
      schema: "github.pull_requests.v1.PullRequestReviewThreadResolveOrUnresolve",
      topic: "github.pull_requests.v1.PullRequestReviewThreadResolve"
    )
  end

  subscribe("pull_request_review_thread.unresolved") do |payload|
    message = {
      pull_request_review_thread: serializer.pull_request_review_thread(payload[:pull_request_review_thread]),
      repository: serializer.repository(payload[:pull_request_review_thread].repository),
      actor: serializer.user(payload[:actor]),
    }

    publish(
      message,
      schema: "github.pull_requests.v1.PullRequestReviewThreadResolveOrUnresolve",
      topic: "github.pull_requests.v1.PullRequestReviewThreadUnresolve"
    )
  end

  subscribe("pull_request_review.submit") do |payload|
    review = payload[:review]

    serialized_changed_files = review.pull_request.changed_files_for_instrumentation.map { |file| serializer.changed_file(file, overrides: { change_type: file.change_type_symbol }) }
    serialized_repository = serializer.repository(review.repository)
    serialized_repository_owner = serializer.user(review.repository.owner)
    serialized_actor = serializer.user(review.user)

    message = {
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      request_context: serializer.request_context(GitHub.context.to_hash),
      pull_request: serializer.pull_request(review.pull_request, overrides: { changed_files: serialized_changed_files }),
      pull_request_review: serializer.pull_request_review(review),
      feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(review.repository).pull_request_scanning_service_flags,
      issue: serializer.issue(review.pull_request.issue),
    }

    message[:comments] = review.review_comments.includes(:pull_request, :automated_review_comment).order(:created_at).limit(100).map { |comment| serializer.pull_request_review_comment(comment) }

    if (github_app_id = GitHub.context[:integration_id])
      message[:github_app_id] = github_app_id
    end

    if payload[:actor]&.feature_flag_enabled?(:copilot_swe_agent_url_trigger, default: false)
      message[:event_url] = serializer.url_for_model(payload[:review])
    end

    publish(message, schema: "github.v1.PullRequestReviewSubmit", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish_secret_scanning_pr_review_scan(review, serialized_repository, serialized_repository_owner, serialized_actor)
  end

  subscribe("pull_request_review.update") do |payload|
    review, old_body = payload.values_at(:review, :old_body)
    serialized_repository = serializer.repository(review.repository)
    serialized_repository_owner = serializer.user(review.repository.owner)
    serialized_actor = serializer.user(review.user)

    message = {
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      pull_request: serializer.pull_request(review.pull_request),
      pull_request_review: serializer.pull_request_review(review),
      old_body: serializer.force_utf8(old_body),
      feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(review.repository).pull_request_scanning_service_flags,
      issue: serializer.issue(review.pull_request.issue),
    }

    publish(message, schema: "github.v1.PullRequestReviewEdit", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

    publish_secret_scanning_pr_review_scan(review, serialized_repository, serialized_repository_owner, serialized_actor)
  end

  subscribe("pull_request_review.dismiss") do |payload|
    review, actor = payload.values_at(:review, :actor)

    message = {
      actor: serializer.user(actor),
      repository: serializer.repository(review.repository),
      pull_request: serializer.pull_request(review.pull_request),
      pull_request_review: serializer.pull_request_review(review),
    }

    publish(message, schema: "github.v1.PullRequestReviewDismiss", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.review_request_delegated") do |payload|
    pull_request_review_request_overrides = {
      actor: serializer.user(payload[:actor]),
      action: serializer.enum_from_string(payload[:action]),
    }

    message = {
      organization: serializer.organization(payload[:organization]),
      team: serializer.team(payload[:team]),
      repository: serializer.repository(payload[:repository]),
      pull_request: serializer.pull_request(payload[:pull_request]),
      algorithm: payload[:algorithm].to_s.upcase,
      max_delegated_reviewers_count: payload[:max_delegated_reviewers_count],
      count_existing_reviewers: payload[:count_existing_reviewers],
      remove_team_request: payload[:remove_team_request],
      include_child_team_members: payload[:include_child_team_members],
      team_review_request: serializer.pull_request_review_request(
        payload[:team_review_request],
        overrides: pull_request_review_request_overrides
      ),
      assigned_review_requests: payload[:assigned_review_requests].map do |assigned_review_request|
        serializer.pull_request_review_request(
          assigned_review_request,
          overrides: pull_request_review_request_overrides
        )
      end
    }

    publish(message, schema: "github.v1.PullRequestReviewRequestDelegation", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.pull_request.select_diff_range") do |payload|
    client_context = payload[:client][:context]
    repository = Repositories.domain.by_id(payload[:repository_id].to_i)
    message = {
      actor: serializer.user(User.find_by(id: payload[:actor_id])),
      repository: serializer.repository(repository),
      pull_request: serializer.pull_request(PullRequest.find_by(id: payload[:pull_request_id])),
      starting_diff_position: client_context[:starting_diff_position],
      ending_diff_position: client_context[:ending_diff_position],
      line_count: client_context[:line_count],
      diff_type: payload[:diff_type],
      whitespace_ignored: payload[:whitespace_ignored],
    }

    publish(message, schema: "github.v1.PullRequestMultilineSelect", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.pull_request.diffbar_filter_by_revision") do |payload|
    pull = PullRequest.find_by(id: payload[:pull_request_id])

    next unless pull.present?

    message = {
      actor: serializer.user(User.find_by(id: payload[:user_id])),
      pull_request: serializer.pull_request(pull),
      repository: serializer.repository(pull.repository),
      current_revision_number: payload[:current_revision_number],
      viewed_revision_number: payload[:viewed_revision_number],
      filter_selection: payload[:filter_selection]
    }

    publish(message, schema: "github.v1.PullRequestDiffbarFilterByRevision", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.pull_request.local_checkout") do |payload|
    message = {
      actor: serializer.user(User.find_by(id: payload[:user_id])),
      action: payload[:action],
      client_type: payload[:client_type],
    }

    publish(message, schema: "github.v1.PullRequestLocalCheckout", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.pull_request.merge_external") do |payload|
    message = {
      actor: serializer.user(User.find_by(id: payload[:user_id])),
      client_type: payload[:client_type],
    }

    publish(message, schema: "github.v1.PullRequestMergeExternal", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.pull-request-refresh") do |payload|
    pr = PullRequest.find_by(id: payload[:pull_request_id])

    message = {
      actor: serializer.user(payload[:client][:user]),
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      pull_request: serializer.pull_request(pr),
      repository: serializer.repository(T.must(pr).repository),
      tab_context: serializer.pull_request_refresh_tab_context(payload[:tab_context]),
    }

    publish(message, schema: "github.v1.PullRequestRefresh", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.force_push_timeline_diff.click") do |payload|
    message = {
      pull_request_id: payload[:pull_request_id],
      repository_id: payload[:repository_id],
      event_id: payload[:event_id],
      user_id: payload[:client]&.[](:user)&.id,
    }

    publish(message, schema: "github.v1.ForcePushTimelineClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.suggested_changes.target.click") do |payload|
    target_type = if payload[:target_type]
      payload[:target_type].upcase.to_sym
    else
      :TARGET_TYPE_UNKNOWN
    end

    relationship_to_suggestion = if payload[:relationship_to_suggestion]
      payload[:relationship_to_suggestion].upcase.to_sym
    else
      :RELATIONSHIP_TYPE_UNKNOWN
    end

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:client][:user]),
      target_type: target_type,
      pull_request_id: payload[:pull_request_id],
      relationship_to_suggestion: relationship_to_suggestion,
    }

    publish(message, schema: "github.v1.SuggestedChangesClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("suggested_change.applied") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      repository_owner: serializer.user(payload[:repository_owner]),
      comment: serializer.pull_request_review_comment(payload[:comment]),
      pull_request: serializer.pull_request(payload[:pull_request]),
      issue: serializer.issue(payload[:issue]),
      file_extension: payload[:file_extension],
      error: payload[:error],
      commit_sha: payload[:commit_sha],
    }

    publish(message, schema: "github.v1.SuggestedChangeApplied", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe(/(browser\.)?pull_request.user_action/) do |payload|
    payload[:data] ||= {}

    # github.v1.PullRequestUserAction schema does not support arbitrary fields, so
    # any 'custom' data from the client context should be merged into the `data` field
    client_context = payload.dig(:client, :context) || {}
    payload[:data][:state] = client_context.delete(:file_filter_checked) if client_context.has_key?(:file_filter_checked)
    payload[:data].merge!(client_context)

    message = {
      actor: serializer.user(User.find_by(id: payload[:user_id])),
      category: payload[:category],
      action: payload[:action],
      data: payload[:data].transform_values(&:to_s),
      request_context: serializer.request_context(GitHub.context.to_hash)
    }

    if payload[:repository_id].present?
      repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
        Repositories.domain.by_id(payload[:repository_id])
      else
        Repository.find_by(id: payload[:repository_id])
      end
      message[:repository] = serializer.repository(repository)
    end

    pull = PullRequest.find_by(id: payload[:pull_request_id])
    message.merge!(
      repository: serializer.repository(pull.repository),
      pull_request: serializer.pull_request(pull)
    ) if pull.present?

    publish(message, schema: "github.v1.PullRequestUserAction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("pull_request.merge_conflict") do |payload|
    pull = payload.fetch(:pull)
    conflicts = payload.fetch(:conflicts)
    publish(
      PullRequests::Conflicts.to_hydro(
        pull: payload.fetch(:pull),
        base_commit_oid: payload.fetch(:base_commit_oid),
        head_commit_oid: payload.fetch(:head_commit_oid),
        conflicts: conflicts.fetch(:conflicted_files),
        more_conflicts_exist: conflicts.fetch(:more_conflicted_files),
        queued: payload.fetch(:queued),
      ),
      schema: "github.pull_requests.v1.MergeConflict",
      partition_key: pull.repository_id
    )
  end

  subscribe("pull_request.mergeability") do |payload|
    mergeable = payload.fetch(:mergeable)
    next unless mergeable == true || mergeable == false

    mergeability_state = mergeable ? :MERGEABLE : :CONFLICTING
    repository_id = payload[:repo_id]

    publish(
      {
        repository_id:,
        pull_request_id: payload.fetch(:pull_request_id),
        mergeability_state:,
      },
      schema: "github.pull_requests.v1.Mergeability",
      partition_key: repository_id
    )
  end

  subscribe("pull_request_stack.update") do |payload|
    repository = payload[:repository]
    next unless repository.present?

    actor = payload[:actor]

    # Serialize pull requests using only in-memory column attributes
    # to avoid triggering additional DB queries.
    serialized_pulls = Array(payload[:pull_requests_affected]).map do |pr|
      {
        id: pr.id,
        pull_request_state: pr_state_from_columns(pr),
        draft: pr.draft,
        head_branch: pr.head_ref,
        base_branch: pr.base_ref,
      }
    end

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      event: payload[:event_type],
      stack: {
        id: payload[:stack_id],
        number: payload[:stack_number],
        base_branch: payload[:stack_base_branch],
      },
      repository: {
        id: repository.id,
        name: repository.name,
        owner_id: { value: repository.owner_id },
        visibility: repository.visibility,
      },
      pull_requests_affected: serialized_pulls,
      stack_size: payload[:stack_size],
      actor: (actor.is_a?(User) ? { id: actor.id, login: actor.login, type: actor.type } : nil),
    }

    publish(message, schema: "github.pull_requests.v1.StackUpdate")
  end

  subscribe("pull_request_stack.merge") do |payload|
    repository = payload[:repository]
    next unless repository.present?

    actor = payload[:actor]

    serialized_pulls = Array(payload[:pull_requests_merged]).map do |pr|
      {
        id: pr.id,
        head_branch: pr.head_ref,
        base_branch: pr.base_ref,
      }
    end

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      merge_action: payload[:merge_action],
      merge_method: payload[:merge_method],
      stack: {
        id: payload[:stack_id],
        number: payload[:stack_number],
        base_branch: payload[:stack_base_branch],
      },
      repository: {
        id: repository.id,
        name: repository.name,
        owner_id: { value: repository.owner_id },
        visibility: repository.visibility,
      },
      pull_requests_merged: serialized_pulls,
      stack_size: payload[:stack_size],
      actor: (actor.is_a?(User) ? { id: actor.id, login: actor.login, type: actor.type } : nil),
    }

    publish(message, schema: "github.pull_requests.v1.StackMerge")
  end

  subscribe("pull_request_change_groups.v0.Feedback") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload.fetch(:organization_id),
        repository_id: payload.fetch(:repository_id),
        pull_request_id: payload.fetch(:pull_request_id),
        head_sha: payload.fetch(:head_sha),
        base_sha: payload.fetch(:base_sha),
        user_analytics_tracking_id: payload.fetch(:analytics_tracking_id),
      },
      type: payload[:type],
    }
    publish(message, schema: "copilot.pull_request_change_groups.v0.Feedback")
  end

  subscribe("pull_request_change_groups.v0.RestrictedFeedback") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        head_sha: payload[:head_sha],
        base_sha: payload[:base_sha],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
      },
      text_response: payload[:text_response],
      feedback_choice: payload[:feedback_choice]
    }

    publish(message, schema: "copilot.pull_request_change_groups.v0.RestrictedFeedback")
  end

  subscribe("pull_request_change_groups.generated") do |payload|
    change_groups = payload[:change_groups]
    orchestration = payload[:orchestration]
    pull_request = payload[:pull_request]

    next unless pull_request.present? && orchestration.present?

    actor = orchestration.actor
    serialized_actor = serializer.user(actor)
    serialized_repository = serializer.repository(pull_request.repository)
    serialized_repository_owner = serializer.user(pull_request.repository.owner)

    # Build pull request with diff stats if available
    pull_request_overrides = build_pull_request_overrides_with_diff_stats(pull_request)
    serialized_pull_request = serializer.pull_request(pull_request, overrides: pull_request_overrides)

    serialized_orchestration = serializer.pull_requests_make_change_groups_orchestration(orchestration)
    message = {
      pull_request: serialized_pull_request,
      actor: serialized_actor,
      repository: serialized_repository,
      repository_owner: serialized_repository_owner,
      group_base_commit_oid: serialized_orchestration[:group_base_commit_oid],
      group_head_commit_oid: serialized_orchestration[:group_head_commit_oid],
      group_state: serialized_orchestration[:state],
      group_step_name: serialized_orchestration[:step_name],
      group_error_message: serialized_orchestration[:error_message],
      groups: change_groups&.map { |group| serializer.pull_request_change_group(group, generate_diff_stats: generate_diff_stats(pull_request)) },
    }
    publish(message, schema: "copilot.pull_request_change_groups.v0.PullRequestChangeGroupsGenerate")
  end

  subscribe("browser.pull-request-hovercard-hover") do |payload|
    pr = PullRequest.find_by(id: payload[:pullRequestOrIssueId])

    message = {
      actor: serializer.user(payload[:client][:user]),
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      pull_request: serializer.pull_request(pr),
      context: serializer.hovercard_context_string(payload[:subject]),
    }

    publish(message, schema: "github.v1.PullRequestHovercardHover", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  def publish_secret_scanning_pr_scan(pr, serialized_repository, serialized_repository_owner, serialized_actor)
    contents = []
    begin
      content_scanning = SecretScanning::Features::Repo::ContentScanning.new(pr.repository)
      if content_scanning.enabled?
        encrypted_title = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(pr.title, pr.issue.id, pr.created_at)
        if encrypted_title.nil?
          GitHub.logger.error(
            "Could not publish pr title for secret scanning",
            "code.namespace": self.class.name,
            "code.function": "publish_secret_scanning_pr_scan",
            "gh.pull_request.id": pr.issue.id,
          )
        else
          contents.push({ content_type: :PULL_REQUEST_TITLE, content: encrypted_title })
        end

        encrypted_body = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(pr.body, pr.issue.id, pr.created_at)
        if encrypted_body.nil?
          GitHub.logger.error(
            "Could not publish pr body for secret scanning",
            "code.namespace": self.class.name,
            "code.function": "publish_secret_scanning_pr_scan",
            "gh.pull_request.id": pr.issue.id,
          )
        else
          contents.push({ content_type: :PULL_REQUEST_BODY, content: encrypted_body })
        end

        scan_msg = {
          repository: serialized_repository,
          owner: serialized_repository_owner,
          actor: serialized_actor,
          content_id: pr.issue.id,
          content_number: pr.number,
          feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(pr.repository).pull_request_scanning_service_flags,
          content_created_at: pr.created_at ? pr.created_at.getutc : nil,
          contents: contents,
        }
        T.unsafe(self).publish(scan_msg, topic: "github.secret_scanning.v1.PullRequestScan", schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
      end
    rescue StandardError => e
      # Prevent secret scanning errors from impacting other teams
      Failbot.report(e)
      GitHub.logger.error(
        "Sending Pull Request Scanning message failed",
        "code.namespace": self.class.name,
        "code.function": "publish_secret_scanning_pull_request_scan",
        "exception.message": e.message,
      )
    end
  end

  def publish_secret_scanning_pr_comment_scan(comment, serialized_repository, serialized_repository_owner, serialized_actor)
    contents = []
    begin
      content_scanning = SecretScanning::Features::Repo::ContentScanning.new(comment.repository)
      if content_scanning.enabled?
        encrypted_body = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(comment.body, comment.id, comment.created_at)
        contents.push({ content_type: :PULL_REQUEST_COMMENT, content: encrypted_body }) unless encrypted_body.nil?

        scan_msg = {
          repository: serialized_repository,
          owner: serialized_repository_owner,
          actor: serialized_actor,
          content_id: comment.id,
          content_number: comment.issue.number, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(comment.repository).pull_request_scanning_service_flags,
          content_created_at: comment.created_at ? comment.created_at.getutc : nil,
          contents: contents,
        }
        T.unsafe(self).publish(scan_msg, topic: "github.secret_scanning.v1.PullRequestCommentScan", schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
      end
    rescue StandardError => e
      # Prevent secret scanning errors from impacting other teams
      Failbot.report(e)
      GitHub.logger.error(
        "Sending Pull Request Scanning message failed",
        "code.namespace": self.class.name,
        "code.function": "publish_secret_scanning_pull_request_comment_scan",
        "exception.message": e.message,
      )
    end
  end

  def publish_secret_scanning_pr_review_scan(review, serialized_repository, serialized_repository_owner, serialized_actor)
    contents = []
    begin
      content_scanning = SecretScanning::Features::Repo::ContentScanning.new(review.repository)
      if content_scanning.enabled?
        body = review.body
        encrypted_body = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(body, review.id, review.created_at)
        # TODO: Change to :PULL_REQUEST_REVIEW once refactor is complete
        contents.push({ content_type: :PULL_REQUEST_TIMELINE_COMMENT, content: encrypted_body }) unless encrypted_body.nil?

        scan_msg = {
          repository: serialized_repository,
          owner: serialized_repository_owner,
          actor: serialized_actor,
          content_id: review.id,
          content_number: review.pull_request.number,
          feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(review.repository).pull_request_scanning_service_flags,
          content_created_at: review.created_at ? review.created_at.getutc : nil,
          contents: contents,
        }
        T.unsafe(self).publish(scan_msg, topic: "github.secret_scanning.v1.PullRequestCommentScan", schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
      end
    rescue StandardError => e
      # Prevent secret scanning errors from impacting other teams
      Failbot.report(e)
      GitHub.logger.error(
        "Sending Pull Request Review Scanning message failed",
        "code.namespace": self.class.name,
        "code.function": "publish_secret_scanning_pull_request_review_scan",
        "exception.message": e.message,
      )
    end
  end

  def publish_secret_scanning_pr_review_comment_scan(review_comment, serialized_repository, serialized_repository_owner, serialized_actor)
    contents = []
    begin
      content_scanning = SecretScanning::Features::Repo::ContentScanning.new(review_comment.repository)
      if content_scanning.enabled?
        body = review_comment.body
        encrypted_body = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(body, review_comment.id, review_comment.created_at)
        contents.push({ content_type: :PULL_REQUEST_REVIEW_COMMENT, content: encrypted_body }) unless encrypted_body.nil?

        scan_msg = {
          repository: serialized_repository,
          owner: serialized_repository_owner,
          actor: serialized_actor,
          content_id: review_comment.id,
          content_number: review_comment.pull_request.number,
          feature_flags: SecretScanning::Instrumentation::RepositoryServiceFlags.new(review_comment.repository).pull_request_scanning_service_flags,
          content_created_at: review_comment.created_at ? review_comment.created_at.getutc : nil,
          contents: contents,
        }
        T.unsafe(self).publish(scan_msg, topic: "github.secret_scanning.v1.PullRequestCommentScan", schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
      end
    rescue StandardError => e
      # Prevent secret scanning errors from impacting other teams
      Failbot.report(e)
      GitHub.logger.error(
        "Sending Pull Request Review Comment Scanning message failed",
        "code.namespace": self.class.name,
        "code.function": "publish_secret_scanning_pull_request_review_comment_scan",
        "exception.message": e.message,
      )
    end
  end

  # Maximum number of changed files before we skip diff stats collection
  # to avoid expensive RPC calls on large PRs
  MAX_DIFF_STATS_FILES = 100

  def generate_diff_stats(pull_request)
    FeatureFlag.vexi.enabled?("pull_requests_hydro_diff_stats", pull_request.user, default: false)
  end

  # Build pull request serialization overrides with diff stats.
  # Collects diff stats synchronously if:
  # - Feature flag is enabled
  # - Cache is warm (data already loaded or summary_warm?)
  # - PR has <= MAX_DIFF_STATS_FILES changed files
  #
  # If conditions aren't met, diff stats are simply omitted.
  #
  # @param pull_request [PullRequest] The pull request to collect diff stats for
  # @param base_overrides [Hash] Base overrides to merge diff stats into
  # @return [Hash] The overrides hash with diff_stats if collected
  def build_pull_request_overrides_with_diff_stats(pull_request, base_overrides = {})
    overrides = base_overrides.dup
    return overrides unless generate_diff_stats(pull_request)

    GitHub.dogstats.time("pull_request.hydro_diff_stats.inline") do
      diff = pull_request.historical_comparison.diffs

      # Only collect if data is already loaded (no RPC) or cache is warm
      if diff.deltas_loaded? || diff.summary_loaded?
        summary = diff.summary

        if summary && summary.changed_files <= MAX_DIFF_STATS_FILES
          overrides[:diff_stats] = Hydro::EntitySerializer.diff_stats(diff)
          GitHub.dogstats.increment("pull_request.hydro_diff_stats.sync_collected")
        else
          GitHub.dogstats.increment("pull_request.hydro_diff_stats.skipped",
            tags: ["reason:too_large"])
        end
      elsif diff.summary_warm?
        # Cache is warm, safe to load
        summary = diff.summary
        if summary && summary.changed_files <= MAX_DIFF_STATS_FILES
          overrides[:diff_stats] = Hydro::EntitySerializer.diff_stats(diff)
          GitHub.dogstats.increment("pull_request.hydro_diff_stats.sync_collected",
            tags: ["source:warm_cache"])
        else
          GitHub.dogstats.increment("pull_request.hydro_diff_stats.skipped",
            tags: ["reason:too_large"])
        end
      else
        # Cache is cold and data not loaded - skip to avoid RPC during sync
        GitHub.dogstats.increment("pull_request.hydro_diff_stats.skipped",
          tags: ["reason:cache_cold"])
      end
    end

    overrides
  end

  # Derives pull request state from in-memory column attributes.
  # We avoid PullRequest#state and PullRequest::Icon::State.for_pull_request
  # because both call open? → issue.open?, which triggers a DB query to
  # load the issue association.
  def pr_state_from_columns(pr)
    if pr.merged_at.present?
      :MERGED
    elsif pr.status == "closed"
      :CLOSED
    elsif pr.status == "open"
      :OPEN
    else
      :UNKNOWN
    end
  end
end
