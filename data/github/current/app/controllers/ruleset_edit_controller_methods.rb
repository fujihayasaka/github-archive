# typed: true
# frozen_string_literal: true

module RulesetEditControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  include ReactHelper
  include Repos::RulesHelper

  requires_ancestor { ApplicationController }
  requires_ancestor { RulesetViewControllerMethods }

  CONTROLLER_METHODS = [
    :ruleset_new,
    :ruleset_destroy,
    :ruleset_update,
    :ruleset_available_properties,
    :ruleset_validate_value,
    :ruleset_validate_import,
    :ruleset_bypass_suggestions,
    :ruleset_repo_suggestions,
    :export_ruleset,
    :ruleset_history_view,
    :ruleset_required_reviewer_suggestions
  ]

  included do
    T.bind(self, T.class_of(ApplicationController))

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Billing,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::Spokes,
      only: [:ruleset_new, :ruleset_history_view, :export_ruleset, :ruleset_available_properties, :ruleset_bypass_suggestions, :ruleset_required_reviewer_suggestions]

    depends_on_clusters ApplicationRecord::Iam, only: [:ruleset_bypass_suggestions]

    before_action :sudo_filter, only: [:ruleset_destroy, :ruleset_update]
  end

  abstract!

  sig { abstract.returns(String) }
  protected def index_path; end

  sig { returns(T::Boolean) }
  protected def read_only?
    false
  end

  sig { returns(String) }
  def title_prefix
    "Settings · "
  end

  def ruleset_new
    if RepositoryRuleset.limit_reached?(current_source)
      return redirect_to index_path, notice: "The ruleset limit has been reached."
    end

    target = params[:target] unless current_source.rules_import_export_local_storage?
    target = params.require(:target) if current_source.rules_import_export_local_storage?

    if target == "push" && (source = current_source).is_a?(Repository) && disallow_editing_push_rules(current_source)
      errors = push_ruleset_validation_errors(source)
      return redirect_to index_path, notice: errors.length > 0 ? errors.join(", ") : nil
    end

    imported_ruleset = params[:imported_ruleset]
    is_imported_ruleset = !!imported_ruleset

    # The import logic is fully client side, so this flag is returned as is to the client
    if (
      is_imported_ruleset &&
      current_source.member_privilege_rulesets_enabled? &&
      !supported_targets.include?(target)
    )
      return redirect_to index_path,
        flash: { error: "The ruleset you are importing is not supported on this page" }
    elsif is_imported_ruleset && !current_source.rules_import_export_local_storage?
      ruleset, import_error = validate_imported_ruleset(current_source, JSON.parse(imported_ruleset))
      return redirect_to index_path, flash: { error: import_error } if import_error
    else
      ruleset = current_source.new_ruleset_with_defaults(target, enforcement: params[:enforcement])
    end

    return render_404 if ruleset.nil?

    render_react_app(
      payload: ruleset_payload(
        current_source:,
        current_user: T.must(current_user),
        ruleset:,
        is_imported_ruleset:,
        no_rulesets: current_source.rulesets.empty?,
      ),
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, supported_features, page_strings) },
      title: "#{title_prefix}Ruleset · #{source_name}",
      page_data: {
        selected_link:,
      },
      layout: layout,
      ssr: true,
    )
  end

  def ruleset_destroy
    ruleset_id = params[:id].to_i

    if !ruleset_id || !ruleset = current_source.rulesets.find_by(id: ruleset_id)
      error_message = "Ruleset not found."
    else
      ruleset.destroy
    end

    if error_message.present?
      if request&.xhr?
        render status: 422, json: { message: error_message }
      else
        flash[:error] = error_message
        redirect_to index_path
      end
    else
      if request&.xhr?
        render status: 200, json: { message: "Ruleset removed." }
      else
        flash[:notice] = "Ruleset removed."
        head 200
      end
    end
  end

  def ruleset_update
    ruleset_json = JSON.parse(request&.body.read)["ruleset"]
    id = ruleset_json["id"]

    # Create the ruleset if it is new
    if id.nil? || id == -1
      ruleset = RepositoryRuleset.new
      ruleset.source = current_source
    else
      ruleset = current_source.ruleset_from_id(id, targets: supported_targets)
      return render_404 unless ruleset.present?
    end

    # Update the ruleset
    error_message, detailed_errors = current_source.update_ruleset_from_json(ruleset, ruleset_json, current_user)

    if error_message.present?
      if request&.xhr?
        render status: 422, json: { message: error_message, detailed_errors: }
      else
        flash[:error] = error_message
        redirect_to index_path
      end
    else
      if request&.xhr?
        ruleset.reload
        render json: Repos::ReactPayload.camelize_keys({ # rubocop:disable GitHub/AvoidCamelizeKeys
          ruleset: RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: current_source, actor: current_user),
          message: "Rules saved.",
          rule_schemas: RulesEngine::ReactPayload.available_rule_schemas(ruleset),
        }), status: 200
      else
        flash[:notice] = "Rules saved."
        redirect_to index_path
      end
    end
  end

  def ruleset_available_properties # rubocop:todo GitHub/UseRestfulActions
    source = current_source
    return render_404 unless source.is_a?(Organization) || source.is_a?(Business)
    ruleset_target = params.require(:ruleset_target) if source.rules_exclude_public_repositories_from_targeting?

    definitions = RepositoryRulesets::PropertyDescriptors.get_descriptors(source)

    payload = {
      properties: definitions.map do |definition|
        {
          name: definition.property_name,
          description: definition.description,
          valueType: definition.value_type,
          allowedValues: definition.get_allowed_values(ruleset_target),
          source: definition.source,
          displayName: definition.display_name,
          icon: definition.icon,
        }
      end
    }
    render json: payload
  end

  def ruleset_validate_value # rubocop:todo GitHub/UseRestfulActions
    type = params.require(:type)
    body = begin JSON.parse(request&.body.read)
    rescue JSON::ParserError, TypeError => e
      nil
    end

    if body.present? && RulesEngine::AsyncValidations.validate_value(current_source, type, body)
      render status: 200, json: { valid: true }
    else
      render status: 400, json: { valid: false }
    end
  end

  def ruleset_validate_import # rubocop:todo GitHub/UseRestfulActions
    imported_ruleset = begin JSON.parse(request&.body.read)
    rescue JSON::ParserError, TypeError => e
      nil
    end

    return render status: 400, json: { message: "Ruleset to import is required" } unless imported_ruleset

    if current_source.member_privilege_rulesets_enabled? &&
      !supported_targets.include?(imported_ruleset&.[]("target"))
      return render status: 400, json: { message: "The ruleset you are importing is not supported on this page" }
    end

    ruleset, import_error = validate_imported_ruleset(current_source, imported_ruleset)

    return render status: 400, json: { message: import_error } if import_error

    ruleset = Repos::ReactPayload.camelize_keys( # rubocop:disable GitHub/AvoidCamelizeKeys
      RulesEngine::ReactPayload.ruleset_json(
        T.must(ruleset),
        viewing_source: current_source,
        include_bypass_actors: true,
        actor: current_user
      )
    )

    render status: 200, json: { ruleset: }
  end

  def ruleset_bypass_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: RulesEngine::Suggestions.bypass_actors_for(
          current_source,
          T.must(current_user),
          query: params[:q].blank? ? nil : params[:q]
        )
      end
    end
  end

  def ruleset_repo_suggestions # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless (source = current_source).is_a?(Organization)

    respond_to do |format|
      format.json do
        render json: RulesEngine::Suggestions.repos_for(
          source,
          params[:q],
          (ActiveModel::Type::Boolean.new.cast(params[:excludePublicRepos]) && source.rules_exclude_public_repositories_from_targeting?) || false,
        )
      end
    end
  end

  def ruleset_org_suggestions # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless (source = current_source).is_a?(Business)

    respond_to do |format|
      format.json do
        render json: RulesEngine::Suggestions.orgs_for(
          source,
          params[:q],
        )
      end
    end
  end

  def ruleset_integration_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: RulesEngine::Suggestions.status_check_integrations_for(current_source)
      end
    end
  end

  def ruleset_required_reviewer_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: RulesEngine::Suggestions.teams_for(
          current_source,
          T.must(current_user),
          query: params[:q],
          filter_repo_results: true,
        )
      end
    end
  end

  def export_ruleset # rubocop:todo GitHub/UseRestfulActions
    ruleset_id = params[:id].to_i
    history_id = params[:history_id]
    if history_id
      history_id = history_id.to_i
      ruleset_history = RepositoryRulesetHistory.find_by(id: history_id, repository_ruleset_id: ruleset_id)
      historical_ruleset = ruleset_history&.ruleset_from_state
      if historical_ruleset.present?
        full_hash = repository_ruleset_hash(historical_ruleset, { request_source: current_source, exporting_ruleset: true })
        render json: sanitize_hash_for_export(full_hash)
      end
    else
      ruleset = current_source.rulesets.find_by(id: ruleset_id)
      full_hash = repository_ruleset_hash(ruleset, { request_source: current_source, exporting_ruleset: true })
      render json: sanitize_hash_for_export(full_hash)
    end
  end

  def ruleset_history_view # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_source.rules_history? && current_source.plan_supports?(:enterprise_rulesets)

    ruleset_id = params.require(:id).to_i
    history_id = params.require(:history_id).to_i

    ruleset = current_source.rulesets.find_by(id: ruleset_id)
    return render_404 unless ruleset.present?

    history = ruleset.histories.find_by(id: history_id)
    return render_404 unless history.present?

    historical_ruleset = history.ruleset_from_state

    render_react_app(
      payload: ruleset_payload(
        current_source: current_source,
        current_user: current_user,
        ruleset: historical_ruleset,
        current_name: ruleset.name,
        read_only: true,
        is_history_view: true,
      ),
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, supported_features, page_strings) },
      title: "#{title_prefix}Ruleset History · #{source_name}",
      page_data: {
        selected_link: selected_link
      },
      layout: layout,
      ssr: true,
    )
  end

end
