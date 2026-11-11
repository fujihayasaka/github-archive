# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotModelRegistryController < StafftoolsController
  include ActionView::Helpers::DateHelper

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:index, :show, :manage, :cache_view, :editor, :new_yaml, :save_yaml, :create_yaml, :delete_yaml, :restore_yaml, :publish_yaml, :validate_yaml, :delete_all_yaml, :pending_changes, :review, :approve, :request_ai_review, :withdraw, :endpoint_health, :add_review_comment]
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Stafftools::CopilotModelRegistryController#save_yaml",
    "Stafftools::CopilotModelRegistryController#create_yaml",
    "Stafftools::CopilotModelRegistryController#delete_yaml",
    "Stafftools::CopilotModelRegistryController#restore_yaml",
    "Stafftools::CopilotModelRegistryController#publish_yaml",
    "Stafftools::CopilotModelRegistryController#validate_yaml",
    "Stafftools::CopilotModelRegistryController#delete_all_yaml",
    "Stafftools::CopilotModelRegistryController#approve",
    "Stafftools::CopilotModelRegistryController#request_ai_review",
    "Stafftools::CopilotModelRegistryController#withdraw",
    "Stafftools::CopilotModelRegistryController#add_review_comment",
  ].freeze, T::Array[String])

  before_action :dotcom_required

  sig { void }
  def index
    show_deleted = params[:show_deleted] == "true"
    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    all_models = model_client.list_yaml_models(include_deleted: show_deleted)
    resolve_actor_ids!(all_models)

    # Fetch pending changes to highlight models with pending reviews
    pending_changes_map = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
    if FeatureFlag.vexi.enabled?(:copilot_model_registry_review_workflow, default: false)
      pending = model_client.list_pending_changes(status: "pending")
      pending.each do |pc|
        ref = pc[:reference_id].to_s
        pending_changes_map[ref] = pc if ref.present?
      end
    end

    filter_type = params[:filter_type].to_s
    filter_value = params[:filter_value].to_s

    models = if filter_type == "vendor" && filter_value.present?
      all_models.select { |m| m[:vendor].to_s == filter_value }
    elsif filter_type == "state" && filter_value.present?
      all_models.select { |m| m[:state].to_s == filter_value }
    else
      all_models
    end

    render "stafftools/copilot_model_registry/manage", locals: {
      models: models,
      all_models: all_models,
      active_filter_type: filter_type,
      active_filter_value: filter_value,
      show_deleted: show_deleted,
      pending_changes_map: pending_changes_map,
    }
  end

  sig { void }
  def cache_view # rubocop:disable GitHub/UseRestfulActions
    registry_models = pull_models
    cached = Copilot::ModelsRegistryCache.all.to_a
    models_diff = Copilot::ModelsRegistryCache.models_changed?(cached, registry_models)
    render "stafftools/copilot_model_registry/cache_view", locals: {
      cached_models: cached,
      registry_models: registry_models,
      models_diff: models_diff,
    }
  end

  sig { void }
  def show
    model_key = params[:id]

    # Fetch full model data from Twirp
    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    full_models = model_client.get_models_full
    model_data = full_models.find { |m| m[:key] == model_key }

    if model_data.nil?
      redirect_to stafftools_copilot_model_registry_index_path, alert: "Model not found" and return
    end

    render "stafftools/copilot_model_registry/show", locals: { model: model_data }
  end

  sig { void }
  def endpoint_health # rubocop:disable GitHub/UseRestfulActions
    model_id = params[:id]

    result = fetch_endpoint_health(model_id.to_s)

    render partial: "stafftools/copilot_model_registry/endpoint_health_detail",
      locals: { health: result[:health], error: result[:error], model_id: model_id }
  rescue => e
    GitHub.logger.info("endpoint_health action failed for #{model_id}: #{e.class} - #{e.message}")
    render partial: "stafftools/copilot_model_registry/endpoint_health_detail",
      locals: { health: nil, error: "Health check failed: #{e.message}", model_id: model_id }
  end

  sig { void }
  def create
    begin
      Copilot::ModelsRegistryCache.save_models
    rescue StandardError => e
      redirect_to cache_view_stafftools_copilot_model_registry_index_path, alert: "Failed to refresh model registry cache: #{e.message}" and return
    end
    redirect_to cache_view_stafftools_copilot_model_registry_index_path, notice: "Model registry cache refreshed"
  end

  sig { void }
  def destroy
    begin
      Copilot::ModelsRegistryCache.clear_models
    rescue StandardError => e
      redirect_to cache_view_stafftools_copilot_model_registry_index_path, alert: "Failed to clear models: #{e.message}" and return
    end
    redirect_to cache_view_stafftools_copilot_model_registry_index_path, notice: "Model registry cache cleared"
  end

  # rubocop:disable GitHub/UseRestfulActions
  sig { void }
  def manage
    redirect_to stafftools_copilot_model_registry_index_path(
      params.permit(:filter_type, :filter_value).to_h
    )
  end

  sig { void }
  def editor # rubocop:disable GitHub/UseRestfulActions
    reference_id = params[:id]
    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    model_data = model_client.get_yaml_model(reference_id)

    unless model_data
      redirect_to stafftools_copilot_model_registry_index_path, alert: "Model '#{reference_id}' not found"
      return
    end

    resolve_actor_ids!([model_data])

    pending_changes = fetch_pending_changes(model_data[:reference_id])

    render "stafftools/copilot_model_registry/editor", locals: {
      model: model_data,
      pending_changes: pending_changes,
    }
  end

  YAML_TEMPLATES = T.let({
    "openai" => "tpl_openai",
    "anthropic" => "tpl_anthropic",
    "google" => "tpl_google",
    "xai" => "tpl_xai",
    "blank" => "tpl_blank",
  }.freeze, T::Hash[String, String])

  sig { void }
  def new_yaml # rubocop:disable GitHub/UseRestfulActions
    template_name = params[:template].to_s
    yaml_content = ""
    if YAML_TEMPLATES.key?(template_name)
      template_file = Rails.root.join("lib/copilot_model_registry/templates/#{template_name}.yaml")
      yaml_content = File.read(template_file) if File.exist?(template_file)
    end
    codename = params[:codename].to_s.strip
    if codename.present? && yaml_content.present?
      yaml_content = yaml_content.gsub("PLACEHOLDER", codename)
    end
    render "stafftools/copilot_model_registry/editor", locals: {
      model: nil,
      selected_template: template_name,
      yaml_content_override: yaml_content.presence,
    }
  end

  sig { void }
  def save_yaml # rubocop:disable GitHub/UseRestfulActions
    reference_id = params[:id]
    yaml_content = params[:yaml_content].to_s

    if params[:validate_only].present?
      return handle_validate_yaml(yaml_content: yaml_content, reference_id: reference_id)
    end

    actor = current_user.id.to_s
    model_client = CopilotModelRegistry::Twirp::ModelClient.new

    # Optimistic concurrency check: detect if model was modified since the editor loaded
    if (conflict = check_concurrency_conflict(model_client, reference_id, params[:loaded_at].to_s, yaml_content))
      return conflict
    end

    if FeatureFlag.vexi.enabled?(:copilot_model_registry_review_workflow, default: false)
      # New review workflow: submit for review instead of direct save
      existing = model_client.get_yaml_model(reference_id)
      target_state = existing&.dig(:state) == "active" ? "published" : "draft"

      result = model_client.submit_yaml_model_change(
        yaml_content: yaml_content,
        target_state: target_state,
        actor: actor,
        reference_id: reference_id,
      )

      if result[:valid]
        redirect_to pending_changes_stafftools_copilot_model_registry_index_path,
          notice: "Changes to '#{reference_id}' submitted for review"
      else
        errors_text = result[:validation_errors].map { |e| "#{e[:field]}: #{e[:message]}" }.join("; ")
        model_data = { reference_id: reference_id, yaml_content: yaml_content, state: "draft" }
        flash.now[:alert] = "Validation failed: #{errors_text}"
        render "stafftools/copilot_model_registry/editor", status: :ok, locals: {
          model: model_data,
          validation_errors: result[:validation_errors],
        }
      end
    else
      # Legacy direct save
      result = model_client.update_yaml_model(reference_id: reference_id, yaml_content: yaml_content, actor: actor)

      if result[:valid]
        redirect_to editor_stafftools_copilot_model_registry_path(reference_id), notice: "Model '#{reference_id}' saved successfully"
      else
        errors_text = result[:validation_errors].map { |e| "#{e[:field]}: #{e[:message]}" }.join("; ")
        model_data = { reference_id: reference_id, yaml_content: yaml_content, state: "draft" }
        flash.now[:alert] = "Validation failed: #{errors_text}"
        render "stafftools/copilot_model_registry/editor", status: :ok, locals: {
          model: model_data,
          validation_errors: result[:validation_errors],
        }
      end
    end
  end

  sig { void }
  def create_yaml # rubocop:disable GitHub/UseRestfulActions
    yaml_content = params[:yaml_content].to_s

    if params[:validate_only].present?
      return handle_validate_yaml(yaml_content: yaml_content, reference_id: nil)
    end

    actor = current_user.id.to_s
    model_client = CopilotModelRegistry::Twirp::ModelClient.new

    if FeatureFlag.vexi.enabled?(:copilot_model_registry_review_workflow, default: false)
      result = model_client.submit_yaml_model_change(
        yaml_content: yaml_content,
        target_state: "draft",
        actor: actor,
      )

      if result[:valid]
        redirect_to pending_changes_stafftools_copilot_model_registry_index_path,
          notice: "New model submitted for review"
      else
        errors_text = result[:validation_errors].map { |e| "#{e[:field]}: #{e[:message]}" }.join("; ")
        flash.now[:alert] = "Validation failed: #{errors_text}"
        render "stafftools/copilot_model_registry/editor", status: :ok, locals: {
          model: nil,
          validation_errors: result[:validation_errors],
          yaml_content_override: yaml_content,
        }
      end
    else
      result = model_client.create_yaml_model(yaml_content: yaml_content, actor: actor)

      if result[:valid]
        redirect_to editor_stafftools_copilot_model_registry_path(result[:reference_id]), notice: "Model '#{result[:reference_id]}' created successfully"
      else
        errors_text = result[:validation_errors].map { |e| "#{e[:field]}: #{e[:message]}" }.join("; ")
        flash.now[:alert] = "Validation failed: #{errors_text}"
        render "stafftools/copilot_model_registry/editor", status: :ok, locals: {
          model: nil,
          validation_errors: result[:validation_errors],
          yaml_content_override: yaml_content,
        }
      end
    end
  end

  sig { void }
  def delete_yaml # rubocop:disable GitHub/UseRestfulActions
    reference_id = params[:id]
    actor = current_user.id.to_s

    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    success = model_client.delete_yaml_model(reference_id: reference_id, actor: actor)

    if success
      redirect_to stafftools_copilot_model_registry_index_path, notice: "Model '#{reference_id}' deleted"
    else
      redirect_to editor_stafftools_copilot_model_registry_path(reference_id), alert: "Failed to delete model '#{reference_id}'"
    end
  end

  sig { void }
  def restore_yaml # rubocop:disable GitHub/UseRestfulActions
    reference_id = params[:id]
    actor = current_user.id.to_s

    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    success = model_client.restore_yaml_model(reference_id: reference_id, actor: actor)

    if success
      redirect_to editor_stafftools_copilot_model_registry_path(reference_id), notice: "Model '#{reference_id}' restored"
    else
      redirect_to stafftools_copilot_model_registry_index_path(show_deleted: true), alert: "Failed to restore model '#{reference_id}'"
    end
  end

  sig { void }
  def delete_all_yaml # rubocop:disable GitHub/UseRestfulActions
    actor = current_user.id.to_s

    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    success = model_client.delete_yaml_db_content(actor: actor)

    if success
      redirect_to stafftools_copilot_model_registry_index_path, notice: "All YAML models, history, pending changes, and reviews permanently deleted"
    else
      redirect_to stafftools_copilot_model_registry_index_path, alert: "Failed to delete all YAML data"
    end
  end

  sig { void }
  def publish_yaml # rubocop:disable GitHub/UseRestfulActions
    reference_id = params[:id]
    actor = current_user.id.to_s
    model_client = CopilotModelRegistry::Twirp::ModelClient.new

    if FeatureFlag.vexi.enabled?(:copilot_model_registry_review_workflow, default: false)
      existing = model_client.get_yaml_model(reference_id)
      unless existing
        redirect_to stafftools_copilot_model_registry_index_path, alert: "Model '#{reference_id}' not found"
        return
      end

      # Don't allow publishing if there are pending changes — those need review first
      existing_pending = model_client.list_pending_changes(reference_id: reference_id, status: "pending")
      if existing_pending.any?
        redirect_to pending_changes_stafftools_copilot_model_registry_index_path,
          alert: "Model '#{reference_id}' has pending changes that must be reviewed first"
        return
      end
    end

    # Publish directly — draft content has already been reviewed/created,
    # this is a state change (draft → published), not a content change.
    success = model_client.publish_yaml_model(reference_id: reference_id, actor: actor)

    if success
      redirect_to stafftools_copilot_model_registry_index_path, notice: "Model '#{reference_id}' published"
    else
      redirect_to stafftools_copilot_model_registry_index_path, alert: "Failed to publish model '#{reference_id}'"
    end
  end

  sig { void }
  def validate_yaml # rubocop:disable GitHub/UseRestfulActions
    yaml_content = params[:yaml_content].to_s
    reference_id = params[:reference_id].to_s.presence

    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    result = model_client.validate_yaml_model(yaml_content: yaml_content, reference_id: reference_id || "")

    if result[:valid]
      flash.now[:notice] = "YAML is valid! No errors found."
    else
      flash.now[:alert] = "Validation failed"
    end

    model = if reference_id
      model_client.get_yaml_model(reference_id) || { reference_id: reference_id, yaml_content: yaml_content, state: "draft" }
    end

    resolve_actor_ids!([model]) if model

    render "stafftools/copilot_model_registry/editor", status: :ok, locals: {
      model: model,
      selected_template: "",
      yaml_content_override: yaml_content,
      validation_errors: result[:validation_errors] || [],
      pending_changes: reference_id ? fetch_pending_changes(reference_id) : [],
    }
  end

  sig { void }
  def pending_changes # rubocop:disable GitHub/UseRestfulActions
    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    status_filter = params[:status].to_s.presence || "pending"
    changes = model_client.list_pending_changes(status: status_filter)
    resolve_pending_change_actors!(changes)

    render "stafftools/copilot_model_registry/pending_changes", locals: {
      pending_changes: changes,
      active_status: status_filter,
    }
  end

  sig { void }
  def review # rubocop:disable GitHub/UseRestfulActions
    pending_change_id = params[:id].to_i
    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    pending_change = model_client.get_pending_change(id: pending_change_id)

    unless pending_change
      redirect_to pending_changes_stafftools_copilot_model_registry_index_path, alert: "Pending change not found"
      return
    end

    # Check submitter before actor IDs are resolved to logins.
    is_submitter = current_user.id.to_s == pending_change[:submitted_by].to_s

    resolve_pending_change_actors!([pending_change])

    # Compute diff
    require "copilot_model_registry/yaml_diff"
    before_yaml = pending_change[:yaml_content_current].presence
    after_yaml = pending_change[:yaml_content_pending].to_s
    diff_lines = CopilotModelRegistry::YamlDiff.compute(before_yaml, after_yaml)
    unified_diff = CopilotModelRegistry::YamlDiff.unified_diff(before_yaml, after_yaml)
    diff_stats = CopilotModelRegistry::YamlDiff.stats(diff_lines)
    is_new = CopilotModelRegistry::YamlDiff.new_model?(before_yaml)

    # Fetch history if this is an existing model
    history_entries = if pending_change[:reference_id].present?
      model_client.get_yaml_model_history(reference_id: pending_change[:reference_id])
    else
      []
    end
    resolve_actor_ids_in_history!(history_entries)

    render "stafftools/copilot_model_registry/review", locals: {
      pending_change: pending_change,
      diff_lines: diff_lines,
      unified_diff: unified_diff,
      diff_stats: diff_stats,
      is_new_model: is_new,
      is_submitter: is_submitter,
      history_entries: history_entries,
      current_user_id: current_user.id.to_s,
      proposed_yaml: after_yaml,
    }
  end

  sig { void }
  def approve # rubocop:disable GitHub/UseRestfulActions
    pending_change_id = params[:id].to_i
    actor = current_user.id.to_s
    comment = params[:comment].to_s

    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    result = model_client.approve_yaml_model_change(
      pending_change_id: pending_change_id,
      actor: actor,
      comment: comment,
    )

    if result[:success]
      redirect_to pending_changes_stafftools_copilot_model_registry_index_path, notice: "Change approved successfully"
    else
      error_details = [result[:error_message]]
      if result[:validation_errors].present?
        error_details += result[:validation_errors].map { |e| e[:message] }
      end
      redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
        alert: "Approval failed: #{error_details.compact.join('; ')}"
    end
  end

  sig { void }
  def withdraw # rubocop:disable GitHub/UseRestfulActions
    pending_change_id = params[:id].to_i

    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    pending_change = model_client.get_pending_change(id: pending_change_id)

    unless pending_change
      redirect_to pending_changes_stafftools_copilot_model_registry_index_path, alert: "Pending change not found"
      return
    end

    # Only the submitter can withdraw their own pending change
    submitted_by = pending_change[:submitted_by].to_s
    if submitted_by.present? && submitted_by != current_user.id.to_s
      redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
        alert: "Only the submitter can withdraw a pending change"
      return
    end

    result = model_client.withdraw_pending_change(pending_change_id: pending_change_id)

    if result[:success]
      redirect_to pending_changes_stafftools_copilot_model_registry_index_path, notice: "Change withdrawn"
    else
      redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
        alert: "Failed to withdraw: #{result[:error_message]}"
    end
  end

  sig { void }
  def add_review_comment # rubocop:disable GitHub/UseRestfulActions
    pending_change_id = params[:id].to_i
    comment = params[:comment].to_s
    review_action = params[:review_action].to_s
    actor = current_user.id.to_s

    if review_action == "approve"
      model_client = CopilotModelRegistry::Twirp::ModelClient.new
      result = model_client.approve_yaml_model_change(
        pending_change_id: pending_change_id,
        actor: actor,
        comment: comment,
      )

      if result[:success]
        redirect_to pending_changes_stafftools_copilot_model_registry_index_path, notice: "Change approved successfully"
      else
        redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
          alert: "Approval failed: #{result[:error_message]}"
      end
      return
    end

    # Default action: add a discussion comment
    if comment.blank?
      redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
        alert: "Comment cannot be empty"
      return
    end

    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    result = model_client.add_review_comment(
      pending_change_id: pending_change_id,
      actor: actor,
      comment: comment,
    )

    if result[:success]
      redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
        notice: "Comment added"
    else
      redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
        alert: "Failed to add comment: #{result[:error_message]}"
    end
  end

  sig { void }
  def request_ai_review # rubocop:disable GitHub/UseRestfulActions
    pending_change_id = params[:id].to_i
    actor = current_user.id.to_s
    model_client = CopilotModelRegistry::Twirp::ModelClient.new

    # Verify the pending change exists
    pending_change = model_client.get_pending_change(id: pending_change_id)
    unless pending_change
      redirect_to pending_changes_stafftools_copilot_model_registry_index_path, alert: "Pending change not found"
      return
    end

    # Request AI review via Twirp (the backend generates and persists the review).
    # NOTE: To generate reviews locally via AiReviewService, the integration ID
    # "copilot-model-registry-review" must first be registered in FEATURE_IDENTIFIERS
    # (config/initializers/copilot_api.rb) with copilot-platform-team approval.
    result = model_client.request_ai_review(pending_change_id: pending_change_id, actor: actor)

    if result
      redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
        notice: "AI review completed"
    else
      redirect_to review_stafftools_copilot_model_registry_path(pending_change_id),
        alert: "AI review request failed"
    end
  end

  private

  # Shared validation handler used by save_yaml and create_yaml when validate_only is set.
  sig { params(yaml_content: String, reference_id: T.nilable(String)).void }
  def handle_validate_yaml(yaml_content:, reference_id:)
    model_client = CopilotModelRegistry::Twirp::ModelClient.new
    result = model_client.validate_yaml_model(yaml_content: yaml_content, reference_id: reference_id || "")

    if result[:valid]
      flash.now[:notice] = "YAML is valid! No errors found."
    else
      flash.now[:alert] = "Validation failed"
    end

    model = if reference_id
      model_client.get_yaml_model(reference_id) || { reference_id: reference_id, yaml_content: yaml_content, state: "draft" }
    end

    resolve_actor_ids!([model]) if model

    render "stafftools/copilot_model_registry/editor", status: :ok, locals: {
      model: model,
      selected_template: "",
      yaml_content_override: yaml_content,
      validation_errors: result[:validation_errors] || [],
      pending_changes: reference_id ? fetch_pending_changes(reference_id) : [],
    }
  end

  # Resolve numeric user IDs in :updated_by to login names.
  # Handles both new format (numeric IDs) and legacy format (usernames) gracefully.
  sig { params(models: T::Array[T::Hash[Symbol, T.untyped]]).void }
  def resolve_actor_ids!(models)
    ids = models.filter_map { |m| m[:updated_by].to_i if m[:updated_by].to_s.match?(/\A\d+\z/) }.uniq
    return if ids.empty?

    logins = User.where(id: ids).pluck(:id, :login).to_h
    models.each do |m|
      val = m[:updated_by].to_s
      next unless val.match?(/\A\d+\z/)

      m[:updated_by] = logins[val.to_i] || "unknown (ID: #{val})"
    end
  end

  # Optimistic concurrency check: detects if the model was modified after the editor loaded.
  # Returns nil if no conflict, or renders the conflict page and returns the render result.
  sig { params(model_client: CopilotModelRegistry::Twirp::ModelClient, reference_id: String, loaded_at_str: String, yaml_content: String).returns(T.untyped) }
  def check_concurrency_conflict(model_client, reference_id, loaded_at_str, yaml_content)
    return nil if loaded_at_str.blank?

    loaded_at = Time.iso8601(loaded_at_str) rescue nil
    return nil unless loaded_at

    current_model = model_client.get_yaml_model(reference_id)
    return nil unless current_model

    current_updated_at = current_model[:updated_at]
    return nil unless current_updated_at
    return nil if current_updated_at <= loaded_at

    # Conflict detected — model was modified since the editor loaded
    resolve_actor_ids!([current_model])

    flash.now[:alert] = "⚠️ Conflict: This model was modified by #{current_model[:updated_by] || 'another user'} " \
      "while you were editing (#{time_ago_in_words(current_updated_at)} ago). " \
      "Your changes have NOT been saved. Please copy your changes below, reload the editor, and re-apply them."

    model_data = {
      reference_id: reference_id,
      yaml_content: current_model[:yaml_content],
      state: current_model[:state],
      updated_at: current_model[:updated_at],
      updated_by: current_model[:updated_by],
      created_at: current_model[:created_at],
    }

    render "stafftools/copilot_model_registry/editor", status: :conflict, locals: {
      model: model_data,
      yaml_content_override: yaml_content,
      concurrency_conflict: {
        your_loaded_at: loaded_at,
        modified_at: current_updated_at,
        modified_by: current_model[:updated_by],
      },
    }
  end

  # Resolve numeric user IDs in pending change :submitted_by and :reviewed_by to login names.
  sig { params(changes: T::Array[T::Hash[Symbol, T.untyped]]).void }
  def resolve_pending_change_actors!(changes)
    ids = changes.flat_map do |c|
      actor_ids = [c[:submitted_by], c[:reviewed_by]].select { |v| v.to_s.match?(/\A\d+\z/) }
      comment_ids = (c[:review_comments] || []).filter_map { |rc| rc[:actor] if rc[:actor].to_s.match?(/\A\d+\z/) }
      actor_ids + comment_ids
    end
    ids = ids.map(&:to_i).uniq
    return if ids.empty?

    logins = User.where(id: ids).pluck(:id, :login).to_h
    changes.each do |c|
      [:submitted_by, :reviewed_by].each do |field|
        val = c[field].to_s
        next unless val.match?(/\A\d+\z/)
        c[field] = logins[val.to_i] || "unknown (ID: #{val})"
      end
      (c[:review_comments] || []).each do |rc|
        val = rc[:actor].to_s
        next unless val.match?(/\A\d+\z/)
        rc[:actor_display] = logins[val.to_i] || "unknown (ID: #{val})"
      end
    end
  end

  # Resolve actor IDs in history entries.
  sig { params(entries: T::Array[T::Hash[Symbol, T.untyped]]).void }
  def resolve_actor_ids_in_history!(entries)
    ids = entries.filter_map { |e| e[:actor].to_i if e[:actor].to_s.match?(/\A\d+\z/) }.uniq
    return if ids.empty?

    logins = User.where(id: ids).pluck(:id, :login).to_h
    entries.each do |e|
      val = e[:actor].to_s
      next unless val.match?(/\A\d+\z/)
      e[:actor] = logins[val.to_i] || "unknown (ID: #{val})"
    end
  end

  sig { returns(T::Array[Copilot::ModelsRegistryCache]) }
  def pull_models
    Copilot::ModelsRegistryCache.pull_models
  end

  sig { params(reference_id: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def fetch_pending_changes(reference_id)
    CopilotModelRegistry::Twirp::ModelClient.new.list_pending_changes(reference_id: reference_id, status: "pending")
  rescue => e
    GitHub.logger.info("Failed to fetch pending changes for #{reference_id}: #{e.message}")
    []
  end

  sig { params(model_id: String).returns(T::Hash[Symbol, T.untyped]) }
  def fetch_endpoint_health(model_id)
    # Get the model's YAML from the registry so we can extract endpoints.
    # This works for ALL models — even those not yet deployed to CAPI.
    # We check both the published model and any pending changes so that
    # endpoint health can be validated before a change is approved.
    endpoints_payload = []
    begin
      model_client = CopilotModelRegistry::Twirp::ModelClient.new
      yaml_content = nil

      # First try the published model.
      yaml_model = model_client.get_yaml_model(model_id)
      yaml_content = yaml_model[:yaml_content] if yaml_model

      # If no published YAML, check for a pending change with updated endpoints.
      if yaml_content.blank?
        pending = model_client.list_pending_changes(reference_id: model_id, status: "pending")
        latest_pending = pending.first
        yaml_content = latest_pending[:yaml_content_pending] if latest_pending
      end

      if yaml_content.present?
        endpoints_payload = parse_endpoints_from_yaml(yaml_content)
      end
    rescue => e
      GitHub.logger.info("Failed to fetch/parse registry YAML for #{model_id}: #{e.class} - #{e.message}")
      endpoints_payload = []
    end

    copilot_api = T.unsafe(CopilotAPI)
    integration_id = T.let(copilot_api.const_get(:COPILOT_CHAT_INTEGRATION_ID), String)
    conn = copilot_api.connection(integration_id: integration_id)
    path = "/models/#{ERB::Util.url_encode(model_id)}/endpoints/health?apiVersion=2023-07-07"

    # POST endpoint data from the registry so CAPI can health-check endpoints
    # for models that aren't shipped yet. Falls back to CAPI's own model lookup
    # if no endpoints are provided.
    response = T.unsafe(conn).post(path, { endpoints: endpoints_payload }.to_json) do |req|
      req.headers[:copilot_integration_id] = integration_id
      req.headers["Content-Type"] = "application/json"
      req.options.timeout = 15
      req.options.open_timeout = 5
    end

    status = T.unsafe(response).status
    if status == 200
      { health: JSON.parse(T.unsafe(response).body, symbolize_names: true), error: nil }
    elsif status == 404
      { health: nil, error: "Model not found in CAPI (HTTP 404). The model may not be deployed yet." }
    elsif status >= 400 && status < 500
      { health: nil, error: "CAPI rejected the request (HTTP #{status}). This is not an endpoint failure — check that the model ID is valid." }
    else
      { health: nil, error: "CAPI returned an unexpected response (HTTP #{status}). This is a CAPI-side issue, not an endpoint failure." }
    end
  rescue Faraday::TimeoutError => e
    GitHub.logger.info("Timeout fetching endpoint health for #{model_id}: #{e.message}")
    { health: nil, error: "Timed out connecting to CAPI. This is a network issue, not an endpoint failure." }
  rescue Faraday::ConnectionFailed => e
    GitHub.logger.info("Connection failed fetching endpoint health for #{model_id}: #{e.message}")
    { health: nil, error: "Could not connect to CAPI. This is a network issue, not an endpoint failure." }
  rescue => e
    GitHub.logger.info("Failed to fetch endpoint health for #{model_id}: #{e.class} - #{e.message}")
    { health: nil, error: "Unable to reach CAPI endpoint health API (#{e.class.name || "Unknown"})" }
  end

  sig { params(yaml_content: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def parse_endpoints_from_yaml(yaml_content)
    parsed = YAML.safe_load(yaml_content)
    return [] unless parsed.is_a?(Hash)

    (parsed["endpoints"] || []).filter_map do |ep|
      next unless ep.is_a?(Hash)

      {
        name: ep["name"],
        url: ep["url"],
        provider: ep["provider"],
        secret_name: ep["secretName"],
        region: ep.dig("region", "fullName"),
      }
    end
  end
end
