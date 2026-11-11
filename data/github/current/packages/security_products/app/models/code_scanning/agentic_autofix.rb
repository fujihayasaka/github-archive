# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AgenticAutofix
    sig { params(repository: Repository, user: T.nilable(User)).returns(T::Boolean) }
    def self.enabled?(repository, user)
      return false unless FeatureFlag.vexi.enabled?(:code_scanning_autofix_use_cca, repository, repository.owner, default: false)

      # Agentic autofix is not enabled if autofix is not enabled for the repository
      return false unless CodeScanning::Autofix.any_enabled_for_repo?(repository)

      return false unless repository.copilot_swe_agent_enabled?(user)

      true
    end

    sig { params(repository: Repository, alert_numbers: T::Array[Integer], current_user: User, analytics_source: T.any(String, Symbol), analytics_labels: T::Array[String], assign_to_copilot: T::Boolean).returns(Turboscan::Proto::StartAgenticAutofixResponse) }
    def self.start_agentic_autofix(repository:, alert_numbers:, current_user:, analytics_source:, analytics_labels: [], assign_to_copilot: true)
      if !repository.copilot_swe_agent_enabled?(current_user)
        raise AgenticAutofixError.new("Copilot cloud agent must be enabled to start agentic autofix", error_type: :cca_disabled, status: :forbidden)
      end

      owner = T.must(repository.owner)
      copilot_swe_agent = T.let(Apps::Privileged.integration(:copilot_swe_agent), T.nilable(Integration))
      if copilot_swe_agent.nil?
        raise AgenticAutofixError.new("Copilot cloud agent integration not found", status: :internal_server_error)
      end

      if repository.default_branch_ref.nil?
        raise AgenticAutofixError.new("Default branch must exist", status: :unprocessable_entity)
      end

      agent_user_id_to_assign = if assign_to_copilot
        copilot_swe_agent.bot&.id
      else
        nil
      end

      request = Turboscan::Proto::StartAgenticAutofixRequest.new(
        repository_id: repository.id,
        owner_id: repository.owner_id,
        alert_numbers: alert_numbers,
        ref_name_bytes: repository.default_branch_ref.qualified_name.b,
        agent_user_id_to_assign:,
        actor_id: current_user.id,
        actor: current_user.display_login,
        org: owner.display_login,
        business_id: owner.business&.id,
        business: owner.business&.slug,
        repository_nwo: repository.name_with_display_owner
      )

      response = GitHub::Turboscan::SuggestedFixes.start_agentic_autofix(request.to_h)

      if response.blank? || response.error.present?
        error_type = T.let(nil, T.nilable(Symbol))
        status = T.let(:internal_server_error, T.any(Symbol, Integer))
        if response&.error.present?
          error = T.must(T.must(response).error)
          meta = error.meta.with_indifferent_access
          if meta.key?(:cca_error) && meta[:cca_error].present?
            error_type = meta[:cca_error].to_sym
            status = Twirp::ERROR_CODES_TO_HTTP_STATUS[error.code] || :internal_server_error
          end
        end

        raise AgenticAutofixError.new("Failed to assign to Copilot. Please try again.", error_type:, status:)
      end

      all_analytics_labels = ["source:#{analytics_source}", "alert_numbers:#{alert_numbers}"] + analytics_labels

      GlobalInstrumenter.instrument("analytics.event",
        actor: current_user,
        category: "code_scanning",
        action: "start_agentic_autofix",
        label: all_analytics_labels.join("; "),
      )

      response.data
    end
  end
end
