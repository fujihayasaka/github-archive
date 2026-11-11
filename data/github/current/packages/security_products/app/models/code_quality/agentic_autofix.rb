# typed: strict
# frozen_string_literal: true

module CodeQuality
  class AgenticAutofix
    sig { params(repository: Repository, user: T.nilable(User)).returns(T::Boolean) }
    def self.enabled?(repository, user)
      return false unless FeatureFlag.vexi.enabled?(:code_quality_agentic_autofix, repository, repository.owner, default: false)

      return false unless repository.copilot_swe_agent_enabled?(user)

      true
    end

    sig { params(repository: Repository, rule_id: String, finding_numbers: T::Array[Integer], current_user: User, analytics_source: T.any(String, Symbol)).returns(Turboquality::Proto::StartAgenticAutofixResponse) }
    def self.start_agentic_autofix(repository:, rule_id:, finding_numbers:, current_user:, analytics_source:)
      default_branch_ref = repository.default_branch_ref
      if default_branch_ref.nil?
        raise CodeScanning::AgenticAutofixError.new("Default branch must exist", status: :unprocessable_entity)
      end

      request = Turboquality::Proto::StartAgenticAutofixRequest.new(
        repository_id: repository.id,
        owner_id: repository.owner_id,
        actor_id: current_user.id,
        finding_numbers: finding_numbers,
        branch_name: default_branch_ref.name,
        rule_id: rule_id,
      )

      response = T.let(GitHub::Turboquality.code_quality_agent_client.start_agentic_autofix(request.to_h), T.nilable(Twirp::ClientResp[Turboquality::Proto::StartAgenticAutofixResponse]))

      if response.blank? || response.error.present?
        error_type = T.let(nil, T.nilable(Symbol))
        status = T.let(:internal_server_error, T.any(Symbol, Integer))
        if (error = response&.error) && error.meta
          meta = error.meta.with_indifferent_access
          if meta.key?(:cca_error) && meta[:cca_error].present?
            error_type = meta[:cca_error].to_sym
            status = Twirp::ERROR_CODES_TO_HTTP_STATUS[error.code] || :internal_server_error
          end
        end

        raise CodeScanning::AgenticAutofixError.new("Failed to assign to Copilot. Please try again.", error_type:, status:)
      end

      all_analytics_labels = ["source:#{analytics_source}", "finding_numbers:#{finding_numbers}", "rule_id:#{rule_id}"]

      GlobalInstrumenter.instrument("analytics.event",
        actor: current_user,
        category: "code_quality",
        action: "start_agentic_autofix",
        label: all_analytics_labels.join("; "),
      )

      response.data
    end
  end
end
