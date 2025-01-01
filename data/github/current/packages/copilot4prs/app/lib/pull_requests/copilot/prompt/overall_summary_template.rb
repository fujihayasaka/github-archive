# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    module Prompt
      class OverallSummaryTemplate < ::Copilot::Prompt::Template
        PromptItem = type_member { { fixed: DiffHunk } }

        sig { returns(PullRequests::Copilot::Prompt::OverallSummary) }
        def prompt
          T.cast(super, PullRequests::Copilot::Prompt::OverallSummary)
        end

        sig { returns(T.nilable(Repository)) }
        def repository
          prompt.pull_request&.base_repository
        end

        sig { returns(T.nilable(String)) }
        def custom_prompt
          prompt.custom_prompt
        end

        sig { returns(T::Boolean) }
        def has_pull_request_template?
          !!(prompt.pull_request&.has_body_template?)
        end

        sig { returns(T.nilable(String)) }
        def pull_request_template
          prompt.pull_request&.body_template
        end

        private

        sig { returns(T::Boolean) }
        def pr_summary_use_template_feature_enabled?
          FeatureFlag.vexi.enabled?(:pr_summary_use_template, prompt.current_user, default: false)
        end
      end
    end
  end
end
