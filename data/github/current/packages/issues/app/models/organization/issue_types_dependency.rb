# typed: strict
# frozen_string_literal: true

module Organization::IssueTypesDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  EXCLUDED_REPOSITORY_LIMIT = 10

  requires_ancestor { Organization }

  sig { returns(T::Boolean) }
  def issue_types_enabled?
    T.bind(self, Organization)
    self.feature_enabled?(:issue_types)
  end

  sig { returns(T.untyped) }
  def setup_issue_types_for_organization
    SetupIssueTypesForOrganizationJob.perform_later(org: self)
  end

  sig { returns(T::Boolean) }
  def issue_type_limit_reached?
    T.bind(self, Organization)
    self.issue_types.count >= IssueType::ORGANIZATION_ISSUE_TYPES_LIMIT
  end

  included do
    T.bind(self, T.class_of(Organization))

    after_create_commit :setup_issue_types_for_organization, unless: -> { GitHub.flipper[:default_issue_types_job_killswitch].enabled? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  end
end
