# typed: strict
# frozen_string_literal: true

module Issue::PlanDependency
  extend T::Helpers

  requires_ancestor { Issue }

  PLAN_FILE_DIRECTORY = ".github/plans"
  PLAN_FILE_PREFIX = "issue-"
  PLAN_FILE_SUFFIX = ".md"
  MAX_PLAN_FILE_SIZE = T.let(256.kilobytes, Integer)
  PLAN_BODY_FEATURE_FLAG = :issues_agentic_plan_body

  sig { returns(String) }
  def plan_file_path
    "#{PLAN_FILE_DIRECTORY}/#{PLAN_FILE_PREFIX}#{number}#{PLAN_FILE_SUFFIX}"
  end

  sig { params(actor: T.nilable(User), repo: Repository).returns(T::Boolean) }
  def plan_feature_enabled?(actor: nil, repo: T.must(repository))
    return false if actor.nil?

    organization = repo.owner.is_a?(Organization) ? repo.owner : nil
    FeatureFlag.vexi.enabled?(PLAN_BODY_FEATURE_FLAG, actor, organization, default: false)
  end
end
