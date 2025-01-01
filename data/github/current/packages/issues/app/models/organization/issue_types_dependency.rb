# typed: strict
# frozen_string_literal: true

module Organization::IssueTypesDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  EXCLUDED_REPOSITORY_LIMIT = 10

  requires_ancestor { Organization }

  sig { returns(T::Boolean) }
  def issue_types_enabled?
    # Orgs will have issue_types enabled by default once issues_react_v2 and related flags are deprecated
    T.bind(self, Organization)
    true
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

    after_create_commit :setup_issue_types_for_organization, unless: -> { FeatureFlag.vexi.enabled_or_raise?(:default_issue_types_job_killswitch) } # rubocop:todo GitHub/AvoidActiveRecordCallbacks, GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  sig do
    params(viewer: T.nilable(User))
    .returns(Promise[{ disabled_allowed: T::Boolean }])
  end
  def async_readable_issue_types_matrix(viewer)
    return Promise.resolve({  disabled_allowed: T.let(false, T::Boolean) }) if viewer.nil?

    # If the viewer is an a valid installation, they can access private and disabled issue types
    if viewer.can_have_granular_permissions?
      return resources.issue_types.async_readable_by?(viewer).then do |readable|
        { disabled_allowed: readable }
      end
    end

    async_member?(viewer).then do |is_member|
      # if the user is a member or collaborator they cannot access disabled issue types
      matrix = { disabled_allowed: false }

      next matrix unless is_member

      # If the viewer is a member, we also need to check if they are an admin, if they are an admin they can also
      # access disabled issue types
      async_adminable_by?(viewer).then do |is_admin|
        matrix[:disabled_allowed] = is_admin

        next matrix
      end
    end
  end
end
