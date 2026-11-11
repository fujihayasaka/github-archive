# typed: true
# frozen_string_literal: true

module RulesetViewControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  include Repos::RulesHelper
  include RepositoryRulesets::HashBuilder
  include FeatureFlagHelper

  GET_CONTROLLER_METHODS = [
    :ruleset_index,
    :ruleset_show,
    :ruleset_history_summary,
    :ruleset_history_comparison,
    :ruleset_repo_suggestions,
  ]

  CONTROLLER_METHODS = [
    :ruleset_deferred_target_counts,
  ].concat(GET_CONTROLLER_METHODS)

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Spokes,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      ApplicationRecord::RepositoriesPushes,
      ApplicationRecord::Iam,
      only: GET_CONTROLLER_METHODS

    depends_on_clusters ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Copilot,
      ApplicationRecord::ActionsEnvironments,
      only: GET_CONTROLLER_METHODS,
      optional: true
  end

  class_methods do
    def react_bundle_name
      "repos-rules"
    end
  end

  abstract!

  sig { abstract.returns(RuleEngine::Types::RuleSource) }
  protected def current_source; end

  sig { abstract.returns(Symbol) }
  protected def selected_link; end

  sig { overridable.returns(Symbol) }
  protected def sidebar_section
    :policies
  end

  sig { abstract.returns(T::Array[String]) }
  protected def supported_targets; end

  sig { abstract.returns(RuleEngine::DomainAccessorBase[T.untyped]) }
  protected def ruleset_domain; end

  sig { overridable.returns(T::Boolean) }
  protected def supports_history?
    true
  end

  sig { overridable.returns(T::Boolean) }
  protected def supports_import_export?
    true
  end

  sig { overridable.returns(T::Boolean) }
  protected def supports_list_view?
    true
  end

  sig { returns(T::Boolean) }
  protected def read_only?
    true
  end

  sig { overridable.returns(T::Boolean) }
  protected def stafftools?
    false
  end

  sig { overridable.returns(String) }
  protected def layout
    "layouts/settings/rules"
  end

  sig { overridable.returns(String) }
  protected def title_prefix
    ""
  end

  PageStrings = T.type_alias do
    {
      heading: String,
      alphaOrBeta: T.nilable(String),
      headingText: String,
      rulesetOrPolicy: String,
      rulesetsOrPolicies: String,
      ruleOrPolicy: String,
      rulesOrPolicies: String,
      upsellHeaderText: String,
      upsellInfoMessage: String,
      protectionsHeading: T.nilable(String),
    }
  end

  sig { overridable.returns(PageStrings) }
  protected def page_strings
    {
      heading: "Rulesets",
      alphaOrBeta: nil,
      headingText: "You haven't created any rulesets",
      rulesetOrPolicy: "ruleset",
      rulesetsOrPolicies: "rulesets",
      ruleOrPolicy: "rule",
      rulesOrPolicies: "rules",
      upsellHeaderText: "Protect your most important branches",
      upsellInfoMessage: "whether collaborators can delete or force push and set requirements for any pushes, such as passing status checks or a linear commit history.",
      protectionsHeading: nil,
    }
  end

  sig { returns(T::Hash[Symbol, String]) }
  def paths
    config_list = if (repo = current_source).is_a?(Repository)
      if stafftools?
        UrlHelpers.stafftools_repository_rules_config_list_path(repo.owner, repo)
      else
        UrlHelpers.repository_rules_config_list_path(repo.owner, repository: repo)
      end
    else
      nil
    end

    {
      configList: config_list,
    }
  end

  def ruleset_index
    return render_404 unless current_source.present?

    ref = current_source.is_a?(Repository) && params[:ref] && params[:ref].is_a?(String) ? Git::Ref.new(current_source, params[:ref]) : nil

    loaded_rulesets = ruleset_domain.load_rulesets(current_source, targets: supported_targets)
    rulesets = if !stafftools? && read_only?
      loaded_rulesets.filter(&:enabled?)
    else
      loaded_rulesets.filter { |ruleset| ruleset.enabled? || ruleset.source == current_source }
    end
    render_react_app(
      payload: ruleset_list_payload(
        current_source:,
        current_user:,
        rulesets:,
        ref:,
        ref_list_cache_key: try(:ref_list_cache_key),
        read_only: read_only?,
        is_stafftools: stafftools?,
        paths:,
        include_implicit_rules: supported_targets == %w[actions],
      ),
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, supported_features, page_strings, is_stafftools: stafftools?) },
      title: "#{title_prefix}#{page_strings[:heading]} · #{source_name}",
      page_data: {
        selected_link:,
        sidebar: sidebar_section,
      },
      layout:,
    )
  end

  def ruleset_show
    ruleset_id = params[:id].to_i
    history_id_to_restore = params[:history_id_to_restore]&.to_i

    if history_id_to_restore && current_source.plan_supports?(:enterprise_rulesets) && supports_history?
      ruleset = ruleset_domain.ruleset_from_id(current_source, ruleset_id, targets: supported_targets)
      return render_404 unless ruleset
      current_name = ruleset.name # use the current ruleset name, not the name of the restored ruleset

      ruleset = T.cast(ruleset, RuleEngine::RulesetBase)
      history = ruleset.histories.find_by(id: history_id_to_restore)

      return render_404 unless history.present?

      historical_ruleset = history.ruleset_from_state
      historical_export = repository_ruleset_hash(historical_ruleset, { request_source: current_source, exporting_ruleset: true })

      ruleset = RepositoryRulesets::HashParser.to_ruleset(ruleset_domain, current_source, historical_export.deep_stringify_keys)
      ruleset.id = ruleset_id
    else
      ruleset = ruleset_domain.ruleset_from_id(current_source, ruleset_id, include_inherited: true, targets: supported_targets)

      return render_404 unless ruleset.present?

      show_errors_on_page_load = !read_only? && (current_source.feature_flag_enabled?(:rulesets_show_errors_on_page_load, default: false) || GitHub.enterprise?)

      if show_errors_on_page_load
        has_errors = T.let(false, T::Boolean)
        initial_errors = { rules: {}, bypass_actors: {}, conditions: {} }

        ruleset.rule_configurations.each do |rule|
          rule = T.cast(rule, RuleEngine::RuleConfigurationBase)
          next unless rule.valid?

          rule.errors.each do |error|
            has_errors = true
            initial_errors[:rules][error.base.rule_type] = error.base.parameter_errors
          end
        end

        initial_errors = nil unless has_errors
      end
    end

    read_only = read_only? || (params[:inherited].present? && params[:inherited] == "true") || ruleset.source != current_source

    render_react_app(
      payload: ruleset_payload(
        current_source: current_source,
        current_user: current_user,
        ruleset: ruleset,
        include_bypass_actors: stafftools? || (!read_only? && ruleset.source == current_source),
        read_only:,
        current_name:,
        is_restored_ruleset: history_id_to_restore.present?,
        initial_errors: initial_errors,
        is_stafftools: stafftools?,
      ),
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, supported_features, page_strings, is_stafftools: stafftools?) },
      title: "#{title_prefix}#{page_strings[:heading]} · #{source_name}",
      page_data: {
        selected_link: selected_link,
        sidebar: sidebar_section,
      },
      layout: layout,
    )
  end

  def ruleset_history_summary
    return render_404 unless (stafftools? || current_source.plan_supports?(:enterprise_rulesets)) && supports_history?
    page = params[:page]&.to_i

    ruleset = ruleset_domain.ruleset_from_id(current_source, params[:id].to_i, targets: supported_targets)

    return render_404 unless ruleset.present?

    render_react_app(
      payload: history_summary_payload(
        current_source: current_source,
        ruleset:,
        page:,
        page_size: PAGE_SIZE,
        is_stafftools: stafftools?,
        read_only: read_only?,
      ),
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, supported_features, page_strings, is_stafftools: stafftools?) },
      title: "#{title_prefix}#{page_strings[:heading]} · History · #{source_name}",
      page_data: {
        selected_link: selected_link,
        sidebar: sidebar_section,
      },
      layout: layout,
    )
  end

  def ruleset_history_comparison
    return render_404 unless (stafftools? || current_source.plan_supports?(:enterprise_rulesets)) && supports_history?

    ruleset = ruleset_domain.ruleset_from_id(current_source, params[:id].to_i, targets: supported_targets)
    return render_404 unless ruleset

    payload = history_comparison_payload(
      source: current_source,
      ruleset: ruleset,
      history_id: params[:history_id]&.to_i,
      compare_history_id: params[:compare_history_id]&.to_i,
      current_user:,
      is_stafftools: stafftools?,
    )

    return render_404 if payload.nil?

    render_react_app(
      payload:,
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, supported_features, page_strings, is_stafftools: stafftools?) },
      title: "#{title_prefix}#{page_strings[:heading]} · History · #{source_name}",
      page_data: {
        selected_link: selected_link,
        sidebar: sidebar_section,
      },
      layout: layout,
    )
  end

  def ruleset_deferred_target_counts
    rulesets_id =
      begin
        JSON.parse(request&.body.read)["ruleset_ids"]
      rescue JSON::ParserError
        []
      end

    respond_to do |format|
      format.json do
        render json: { preview: ::RulesEngine::RulesetMatcher.rulesets_target_count(ruleset_domain, current_source, rulesets_id, supported_targets:) }
      end
    end
  end

  def ruleset_repo_suggestions
    return render_404 unless (source = current_source).is_a?(Organization)

    respond_to do |format|
      format.json do
        render json: RulesEngine::Suggestions.repos_for(
          source,
          params[:q],
          ActiveModel::Type::Boolean.new.cast(params[:excludePublicRepos]) || false,
        )
      end
    end
  end

  protected

  sig { returns(RulesEngine::ReactPayload::RuleFeatures) }
  def supported_features
    targets = disallow_editing_push_rules(current_source) ? supported_targets - ["push"] : supported_targets
    {
      supportedTargets: targets,
      targetDefinitions: targets.to_h do |target|
        [target, RulesetDefinitions::RulesetDefinition.ui_definition(target)]
      end,
      historyEnabled: supports_history?,
      importExportEnabled: supports_import_export?,
      listViewEnabled: supports_list_view?,
    }
  end

  def source_name
    source = current_source
    if source.is_a?(Business) || source.is_a?(Repository)
      source.name
    else
      source.display_login
    end
  end

  private

  sig do
    params(
      current_source: RuleEngine::Types::RuleSource,
    ).returns(T::Boolean)
  end
  def disallow_editing_push_rules(current_source)
    current_source.is_a?(Repository) && (
      current_source.public? ||
      current_source.fork? ||
      !current_source.owner.is_a?(Organization)
    )
  end
end
