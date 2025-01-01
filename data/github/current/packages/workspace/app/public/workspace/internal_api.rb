# typed: strict
# frozen_string_literal: true

module Workspace
  class InternalApi
    FEATURE_FLAGS = [
      :copilot_workspace_capi_file_selection,
      :copilot_workspace_offline,
      :copilot_workspace_offline_override,
      :copilot_workspace_session_history,
      :copilot_workspace_skip_waitlist,
      :copilot_workspace_sonnet,
      :copilot_workspace_use_capi,
      :copilot_workspace_sunset_banner,
    ]

    sig { params(current_user: ::User).void }
    def initialize(current_user)
      @current_user = current_user
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def response
      # We compute this locally rather than at the class level
      # because after some changes we look it up and replace it.
      copilot_user = Copilot::User.new(@current_user)

      feature_flags = FEATURE_FLAGS.map { |flag| [flag, @current_user.feature_enabled?(flag)] }.to_h

      response = {
        copilot_workspace_enabled: workspace_enabled?(copilot_user),
        spark_enabled: copilot_user.spark_enabled?,
        feature_flags:,
      }

      begin
        if @current_user.copilot_workspace_can_grant_auto_access?
          enable_copilot_workspace
          # find current user again to get the updated feature_enabled value which was memoized as false. Reloading the user object doesn't work.
          copilot_user = Copilot::User.new(::User.find(@current_user.id))
          response[:copilot_workspace_enabled] = workspace_enabled?(copilot_user)
        end
      rescue ActiveRecord::RecordInvalid => e
        GitHub.logger.error("Error granting user access to Copilot Workspace", "error" => e)
      end

      if @current_user.feature_enabled?(:copilot_workspace_capacity_grants)
        response[:copilot_workspace_max_codespace_users] = Codespaces::Dials::CopilotWorkspaceMaxCodespaceUsers.new.value
        response[:copilot_workspace_max_model_users] = Codespaces::Dials::CopilotWorkspaceMaxModelUsers.new.value
      end

      response
    end

    sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
    def workspace_enabled?(copilot_user)
      copilot_user.workspace_enabled? &&
        !copilot_user.administrative_blocked? &&
        !@current_user.feature_enabled?(:copilot_workspace_force_no_access)
    end

    sig { returns(T::Boolean) }
    def enable_copilot_workspace
      # Find or create waitlist membership
      user_on_waitlist = EarlyAccessMembership.copilot_workspace_waitlist.find_by(member: @current_user)

      # if membership not found, create a new one
      if user_on_waitlist.nil?
        survey = Copilot::WorkspaceWaitlistSurvey.find_survey
        user_on_waitlist = EarlyAccessMembership.new(
          member_id: @current_user.id,
          actor_id: @current_user.id,
          feature_slug: Copilot::WorkspaceBeta.new.feature_slug,
          survey: survey,
        )
        # User has to agree to the terms to access Workspace
        # When they confirmed to sign in to GitHub they agreed to the GitHub Next terms
        question = survey.questions.find_by_short_text("github_next_prerelease_terms")
        choice = question.choices.find_by_short_text("agree_github_next_prerelease_terms")
        terms_survey_answers = [{
          question_id: question.id,
          choice_id: choice.id
        }]
        ActiveRecord::Base.connected_to(role: :writing) do
          user_on_waitlist.save_with_survey_answers(terms_survey_answers)
        end
      end

      # Enable the feature from their waitlist entry
      # They will not get an email mailer this way
      ActiveRecord::Base.connected_to(role: :writing) do
        user_on_waitlist.update!(feature_enabled: true)
      end
    end
  end
end
