# typed: true
# frozen_string_literal: true

require "delegate"

class CombinedStatus
  class CheckRunAdapter < SimpleDelegator
    def state
      (T.unsafe(self).conclusion || T.unsafe(self).status).to_s
    end

    def state_changed_at
      T.unsafe(self).completed_at || T.unsafe(self).started_at || T.unsafe(self).created_at
    end

    # This method is especially important because it's used in protected branch rules
    def context
      T.unsafe(self).visible_name
    end

    def description
      T.unsafe(self).title
    end

    def platform_type_name
      "CheckRun"
    end

    def duration_in_seconds
      return 0 if !T.unsafe(self).completed_at
      return 0 if T.unsafe(self).completed_at > Time.now.utc

      (T.unsafe(self).completed_at - (T.unsafe(self).started_at || T.unsafe(self).completed_at)).floor
    end

    # The view means OAuth Application
    # when it says application.
    def application
      nil
    end

    def target_url(pull: nil)
      T.unsafe(self).permalink(pull: pull)
    end

    def sha
      T.unsafe(self).head_sha
    end

    def integration_id
      T.unsafe(self).check_suite.github_app_id
    end

    # === Implement these to appease Sorbet (which really doesn't like these delegate classes)
    def integration
      T.bind(self, T.untyped)
      super
    end

    def is_a?(a)
      T.bind(self, T.untyped)
      super
    end

    def check_suite
      T.bind(self, T.untyped)
      super
    end

    def check_suite_id
      T.bind(self, T.untyped)
      super
    end

    def required_for_pull_request?(...)
      T.bind(self, T.untyped)
      super
    end

    def contextual_name
      T.bind(self, T.untyped)
      super
    end
    # ===

    def commit_oid
      T.unsafe(self).head_sha
    end

    # This would be much nicer if it were `application`,
    # but the view won't do the right thing if we do that.
    def creator
      T.unsafe(self).github_app&.bot || User.ghost
    end

    def tree_oid
      T.unsafe(self).check_suite.repository.commits.find(T.unsafe(self).check_suite.head_sha).tree_oid
    end

    sig { returns(T::Boolean) }
    def eligible_for_copilot_failure_analysis?
      return false unless T.unsafe(self).id
      return false unless T.unsafe(self).conclusion&.downcase == "failure"
      return false unless T.unsafe(self).is_actions_check_run?
      return false unless T.unsafe(self).workflow_job_run.present?
      true
    end
  end
end
