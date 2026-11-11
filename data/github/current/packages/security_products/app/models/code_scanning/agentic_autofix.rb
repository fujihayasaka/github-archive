# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AgenticAutofix
    sig { params(repository: Repository, alert_numbers: T::Array[Integer], current_user: User, assign_to_copilot: T::Boolean).returns(Turboscan::Proto::StartAgenticAutofixResponse) }
    def self.start_agentic_autofix(repository:, alert_numbers:, current_user:, assign_to_copilot: true)
      if !repository.copilot_swe_agent_enabled?(current_user)
        raise AgenticAutofixError.new("Copilot Coding Agent must be enabled to start agentic autofix", status: :forbidden)
      end

      owner = T.must(repository.owner)
      copilot_swe_agent = T.let(Apps::Privileged.integration(:copilot_swe_agent), T.nilable(Integration))
      if copilot_swe_agent.nil?
        raise AgenticAutofixError.new("Copilot Coding Agent integration not found", status: :internal_server_error)
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
        raise AgenticAutofixError.new("Failed to assign to Copilot. Please try again.", status: :internal_server_error)
      end

      response.data
    end
  end
end
