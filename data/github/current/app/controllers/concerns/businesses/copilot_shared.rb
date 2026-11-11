# typed: strict
# frozen_string_literal: true

module Businesses::CopilotShared
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Businesses::BusinessController }

  private

  sig { returns(Copilot::Business) }
  def copilot_business
    @copilot_business ||= T.let(Copilot::Business.new(this_business), T.nilable(Copilot::Business))
  end

  sig { returns(T::Boolean) }
  def standalone_business?
    copilot_business.copilot_standalone?
  end

  sig { void }
  def ensure_not_standalone_copilot_business
    render_404 if standalone_business?
  end

  sig { returns(String) }
  def get_features_for_data_retention
    return "" unless copilot_business.copilot_plan_business?

    features = []
    features << Copilot::COPILOT_IN_DOTCOM if copilot_business.has_copilot_enterprise_access? && !standalone_business?
    features << Copilot::COPILOT_CHAT_IN_MOBILE
    features << Copilot::COPILOT_SWE_AGENT if (!GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, this_business, default: false)) && !standalone_business?
    return "Enabling #{features.to_sentence} will collect additional data" if !features.empty?
    ""
  end

  sig { returns(T::Boolean) }
  def render_copilot_feedback_opt_in_settings?
    copilot_business.copilot_for_dotcom_enabled?
  end

  sig { returns(T::Boolean) }
  def render_copilot_beta_features_opt_in_settings?
    return true if copilot_business.copilot_for_dotcom_enabled?

    T.must(copilot_business.copilot_for_dotcom_enabled? &&
      copilot_business.copilot_organizations.any? { |org| org.copilot_enabled? && org.copilot_plan_enterprise? })
  end

  sig { returns(T::Boolean) }
  def render_copilot_swe_agent_settings?
    Copilot::Policies::CodingAgent.available_for?(copilot_business)
  end

  sig { returns(T::Boolean) }
  def render_copilot_code_review_settings?
    Copilot::Policies::CodeReview.available_for?(copilot_business)
  end

  sig { returns(T::Boolean) }
  def render_copilot_code_review_beta_features_settings?
    copilot_business.code_review_enabled?
  end

  sig { returns(T::Boolean) }
  def render_ccr_direct_org_billing_settings?
    return false unless copilot_business.feature_flag_enabled?(:copilot_code_review_direct_org_billing, default: false)

    copilot_business.code_review_enabled?
  end

  sig { returns(T::Boolean) }
  def render_cca_direct_org_billing_settings?
    return false unless copilot_business.feature_flag_enabled?(:copilot_coding_agent_direct_org_billing, default: false)

    copilot_business.swe_agent_enabled? || copilot_business.coding_agent_enterprise_management_enabled?
  end

  sig { returns(T::Boolean) }
  def render_cli_direct_org_billing_settings?
    return false unless copilot_business.feature_flag_enabled?(:copilot_cli_direct_org_billing, default: false)

    copilot_business.cli_enabled?
  end

  sig { returns(T::Boolean) }
  def render_cli_remote_control_settings?
    return false unless copilot_business.feature_flag_enabled?(:copilot_cli_remote_control, default: false)

    copilot_business.cli_enabled? || copilot_business.cli_no_policy?
  end

  sig { returns(T::Boolean) }
  def render_copilot_memory_exports_settings?
    copilot_business.feature_flag_enabled?(:copilot_memory_admin_exports, default: false)
  end

  sig { returns(T::Boolean) }
  def render_cli_cloud_session_storage_settings?
    return false unless Copilot::Policies::CliCloudSessionStorage.available_for?(copilot_business)

    copilot_business.cli_enabled? || copilot_business.cli_no_policy?
  end

  sig { returns(Copilot::User) }
  def current_copilot_user
    @current_copilot_user ||= T.let(Copilot::User.new(current_user), T.nilable(Copilot::User))
    @current_copilot_user
  end

  sig { returns(ActiveRecord::Relation) }
  def feature_requests_from_admins
    @feature_requests_from_admins ||= T.let(
      if MemberFeatureRequest.break_joins_enabled?
        MemberFeatureRequest.where(billing_entity: this_business)
          .where(request_entity_id: business_org_ids + [nil])
          .includes(:request_entity, :requester)
      else
        MemberFeatureRequest.active_request_entities.where(billing_entity: this_business).includes(:request_entity, :requester)
      end,
      T.nilable(ActiveRecord::Relation),
    )
    @feature_requests_from_admins
  end

  sig { void }
  def ensure_trial_business_is_dfd_trial_or_contains_cfb_trial
    return unless this_business.trial?
    return if this_business.dfd_trial?
    return if this_business.digital_front_door?
    render_404 unless copilot_business.has_trial_organization?
  end

  sig { void }
  def handle_ai_controls_trial_entry_flow
    return if performed?
    return unless ai_controls_trial_guard_applicable?

    if dfd_trial_business_without_cfb_trial?
      render_ai_controls_trial_gate
      return
    end

    return unless copilot_business.eligible_for_first_run_flow?

    render_ai_controls_first_run_flow
  end

  sig { overridable.returns(String) }
  def ai_controls_section_title
    "Copilot"
  end

  sig { overridable.returns(Symbol) }
  def ai_controls_selected_link
    :businesses_ai_controls_copilot
  end

  sig { returns(T::Boolean) }
  def ai_controls_trial_guard_applicable?
    FeatureFlag.vexi.enabled?("enterprise_ai_controls", this_business, default: false) &&
      !!this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end

  sig { overridable.void }
  def render_ai_controls_trial_gate
    render "businesses/ai_controls/dfd_trial_without_copilot_business_trial", locals: {
      this_business: this_business,
      title: ai_controls_section_title,
      selected_link: ai_controls_selected_link,
    }
  end

  sig { overridable.void }
  def render_ai_controls_first_run_flow
    render "businesses/ai_controls/first_run_flow_cta", locals: {
      this_business: this_business,
      title: ai_controls_section_title,
      selected_link: ai_controls_selected_link,
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
      is_admin: this_business&.adminable_by?(current_user) || false,
    }
  end

  sig { returns(ActiveRecord::Relation) }
  def feature_requests_from_members_of_organizations
    @feature_requests_from_members_of_organizations ||= T.let(
      if MemberFeatureRequest.break_joins_enabled?
        MemberFeatureRequest.where(billing_entity: business_org_ids)
          .includes(:request_entity, :requester)
      else
        MemberFeatureRequest.active_request_entities.where(billing_entity: this_business.organizations.pluck(:id)).includes(:request_entity, :requester)
      end,
      T.nilable(ActiveRecord::Relation),
    )
    @feature_requests_from_members_of_organizations
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def feature_requests_count_by_organizations
    MemberFeatureRequest.feature_requests_count_by_organizations(
      admin_feature_requests: feature_requests_from_admins,
      member_feature_requests: feature_requests_from_members_of_organizations,
    )
  end

  sig { returns(T::Array[Integer]) }
  def business_org_ids
    @business_org_ids ||= T.let(
      this_business.organizations.pluck(:id),
      T.nilable(T::Array[Integer]),
    )
    @business_org_ids
  end

  sig { returns(T::Boolean) }
  def dfd_trial_business_without_cfb_trial?
    return false unless this_business.trial?
    return false unless this_business.dfd_trial?
    # This method can be deleted once the feature flag below is shipped
    return false if this_business.digital_front_door?
    !copilot_business.has_trial_organization?
  end

  sig { returns(T::Array[::Organization]) }
  def paginated_orgs
    page = params[:page] || 1

    if feature_requests_from_admins.any? || feature_requests_from_members_of_organizations.any?
      MemberFeatureRequest.sorted_organizations_by_features(
        organizations: this_business.organizations,
        admin_feature_requests: feature_requests_from_admins,
        member_feature_requests: feature_requests_from_members_of_organizations,
      ).paginate(page: page, per_page: copilot_per_page).to_a
    else
      this_business.organizations.paginate(page: page, per_page: copilot_per_page).to_a
    end
  end

  sig { returns(T::Array[::Organization]) }
  def orgs_matching_query
    page = params[:page] || 1
    query = params[:query]
    this_business.organizations.where("`login` like ?", "%#{query}%").paginate(page: page, per_page: copilot_per_page).to_a
  end

  sig { returns(Integer) }
  def copilot_per_page
    value = if self.class.const_defined?(:PER_PAGE)
      self.class.const_get(:PER_PAGE)
    else
      10
    end

    T.cast(value, Integer)
  end

  sig { returns(String) }
  def content_exclusions_audit_link
    query = Search::Queries::AuditLogQuery.stringify(["action:#{Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED}"])
    settings_audit_log_enterprise_path(this_business, q: query)
  end

  sig { returns(T.untyped) }
  def content_exclusions_partial_payload
    config = Copilot::ContentExclusionConfiguration.for_business(this_business).first

    {
      endpoint: update_settings_copilot_content_exclusion_enterprise_path(this_business),
      lastEdited: config&.updated_by ? { login: config.updated_by&.display_login, time: config.updated_at, link: content_exclusions_audit_link } : nil,
      document: config&.document,
    }
  end

  sig { returns(T::Array[T.all(Copilot::PolicyInterface, Copilot::Policies::Concerns::Mutable)]) }
  def available_models_for_business
    @available_models_for_business ||= T.let(
      Copilot::Policies::MODELS.select do |model|
        next false if model.config_name == "ofo" && !copilot_business.feature_flag_enabled?(:copilot_api_force_legacy_base_chat_model, default: false)
        next true unless model.respond_to?(:available_for?)

        model.available_for?(copilot_business)
      end,
      T.nilable(T::Array[T.all(Copilot::PolicyInterface, Copilot::Policies::Concerns::Mutable)])
    )
  end
end
