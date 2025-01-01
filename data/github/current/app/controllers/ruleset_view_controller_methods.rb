# typed: true
# frozen_string_literal: true

module RulesetViewControllerMethods
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  include ReactHelper
  include Repos::RulesHelper
  include RepositoryRulesets::HashBuilder
  include FeatureFlagHelper


  CONTROLLER_METHODS = [:ruleset_index, :ruleset_show, :ruleset_history_summary, :ruleset_history_comparison]

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
      only: CONTROLLER_METHODS

    depends_on_clusters ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Copilot,
      only: CONTROLLER_METHODS,
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

  sig { abstract.returns(T::Array[String]) }
  protected def supported_targets; end

  sig { overridable.returns(T::Boolean) }
  protected def supports_history?
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

  def ruleset_index
    ref = current_source.is_a?(Repository) && params[:ref] && params[:ref].is_a?(String) ? Git::Ref.new(current_source, params[:ref]) : nil

    render_react_app(
      payload: ruleset_list_payload(
        current_source: current_source,
        current_user: current_user,
        rulesets: current_source.filtered_inherited_rulesets(enabled_only: !stafftools? && read_only?, targets: supported_targets),
        supported_targets:,
        ref:,
        ref_list_cache_key: try(:ref_list_cache_key),
        read_only: read_only?,
        is_stafftools: stafftools?,
      ),
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, is_stafftools: stafftools?) },
      title: "#{title_prefix}Rulesets · #{source_name}",
      page_data: {
        selected_link: selected_link
      },
      layout: layout,
      ssr: true,
    )
  end

  def ruleset_show
    ruleset_id = params[:id].to_i
    history_id_to_restore = params[:history_id_to_restore]&.to_i

    if current_source.rules_history? && history_id_to_restore && current_source.plan_supports?(:enterprise_rulesets) && supports_history?
      ruleset = current_source.rulesets.find_by(id: ruleset_id)
      return render_404 unless ruleset
      current_name = ruleset.name # use the current ruleset name, not the name of the restored ruleset
      history = ruleset.histories.find_by(id: history_id_to_restore)

      return render_404 unless history.present?

      ruleset = current_source.rulesets.build
      historical_ruleset = history.ruleset_from_state
      historical_export = repository_ruleset_hash(historical_ruleset, { request_source: current_source, exporting_ruleset: true })

      ruleset = RepositoryRulesets::HashParser.to_repository_ruleset(current_source, historical_export.deep_stringify_keys)
      ruleset.id = ruleset_id
    else
      ruleset = current_source.ruleset_from_id(ruleset_id, include_inherited: true, targets: supported_targets)

      return render_404 unless ruleset.present?

      show_errors_on_page_load = !read_only? && (current_source.feature_enabled?(:rulesets_show_errors_on_page_load) || GitHub.enterprise?)

      if show_errors_on_page_load
        has_errors = T.let(false, T::Boolean)
        initial_errors = { rules: {}, bypass_actors: {}, conditions: {} }

        ruleset.rule_configurations.each do |rule|
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
        is_restored_ruleset: current_source.rules_history? && history_id_to_restore.present?,
        initial_errors: initial_errors,
        is_stafftools: stafftools?,
      ),
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, is_stafftools: stafftools?) },
      title: "#{title_prefix}Ruleset · #{source_name}",
      page_data: {
        selected_link: selected_link
      },
      layout: layout,
      ssr: true,
    )
  end

  def ruleset_history_summary  # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_source.rules_history? && (stafftools? || current_source.plan_supports?(:enterprise_rulesets)) && supports_history?
    page = params[:page]&.to_i

    ruleset = current_source.rulesets.find_by(id: params[:id])

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
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, is_stafftools: stafftools?) },
      title: "#{title_prefix}Ruleset · History · #{source_name}",
      page_data: {
        selected_link: selected_link
      },
      layout: layout,
      ssr: true,
    )
  end

  def ruleset_history_comparison # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_source.rules_history? && (stafftools? || current_source.plan_supports?(:enterprise_rulesets)) && supports_history?

    ruleset = current_source.rulesets.find_by(id: params[:id].to_i)
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
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, is_stafftools: stafftools?) },
      title: "#{title_prefix}Ruleset · History · #{source_name}",
      page_data: {
        selected_link: selected_link
      },
      layout: layout,
      ssr: true,
    )
  end

  def ruleset_deferred_target_counts # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_source.is_a?(Organization) || current_source.is_a?(Repository)

    return render_404 unless ::RulesEngine::RulesetMatcher.async_preview_ff_enabled?(current_source, current_user)

    rulesets_id =
      begin
        JSON.parse(request&.body.read)["ruleset_ids"]
      rescue JSON::ParserError
        []
      end

    respond_to do |format|
      format.json do
        render json: { preview: ::RulesEngine::RulesetMatcher.rulesets_target_count(current_source, rulesets_id) }
      end
    end
  end

  protected

  def source_name
    source = current_source
    if source.is_a?(Business) || source.is_a?(Repository)
      source.name
    else
      source.display_login
    end
  end
end
