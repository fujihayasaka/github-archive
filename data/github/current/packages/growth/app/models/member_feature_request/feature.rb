# typed: strict
# frozen_string_literal: true

class MemberFeatureRequest::Feature < T::Enum
  extend GitHub::ResilienceMixin

  enums do
    ProtectedBranches = new(0)
    CustomRepositoryRoles = new(1)
    DraftPullRequests = new(2)
    CopilotForBusiness = new(3)
    Rulesets = new(4)
  end

  sig { params(org: Organization).returns(T::Array[MemberFeatureRequest::Feature]) }
  def self.not_included_in_org(org)
    values.select do |feature|
      # Each add-on has different way to check if it's enabled for the org.
      # For non add-on features, we can use the plan to check if it's supported.
      case feature
      when CopilotForBusiness
        with_database_error_fallback(fallback: false) do
          !Copilot::Organization.new(org).has_copilot_for_business?
        end
      else
        !org.plan.supports?(feature.metadata[:feature_key], visibility: :private)
      end
    end
  end

  sig { params(value: T.nilable(MemberFeatureRequest::Feature)).returns(T.nilable(Integer)) }
  def self.dump(value)
    value&.serialize
  end

  sig { params(value: T.nilable(Integer)).returns(T.nilable(MemberFeatureRequest::Feature)) }
  def self.load(value)
    deserialize(value) if value
  end

  sig { params(value: String).returns(T.nilable(MemberFeatureRequest::Feature)) }
  def self.from_string(value)
    {
      protected_branches: MemberFeatureRequest::Feature::ProtectedBranches,
      custom_repository_roles: MemberFeatureRequest::Feature::CustomRepositoryRoles,
      draft_pull_requests: MemberFeatureRequest::Feature::DraftPullRequests,
      copilot_for_business: MemberFeatureRequest::Feature::CopilotForBusiness,
      rulesets: MemberFeatureRequest::Feature::Rulesets,
    }[value.to_sym]
  end

  sig { returns(String) }
  def to_s
    {
      MemberFeatureRequest::Feature::ProtectedBranches => "protected_branches",
      MemberFeatureRequest::Feature::CustomRepositoryRoles => "custom_repository_roles",
      MemberFeatureRequest::Feature::DraftPullRequests => "draft_pull_requests",
      MemberFeatureRequest::Feature::CopilotForBusiness => "copilot_for_business",
      MemberFeatureRequest::Feature::Rulesets => "rulesets",
    }[self]
  end

  sig { returns(T::Boolean) }
  def enterprise_only?
    metadata[:plans] == [GitHub::Plan.business_plus]
  end

  sig { returns(T::Boolean) }
  def add_on?
    !!metadata[:add_on]
  end

  sig { returns(String) }
  def name
    metadata[:name]
  end

  sig { returns(Symbol) }
  def icon
    metadata[:icon]
  end

  sig { returns(String) }
  def docs_url
    metadata[:docs_url]
  end

  sig { returns(String) }
  def formatted_text
    metadata[:formatted_text]
  end

  sig { returns(String) }
  def description
    metadata[:description]
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def metadata
    case self
    when ProtectedBranches then
      {
        name: "Protected branches",
        description: "Enforce how branches are merged by requiring reviews, or allowing specific contributors to work on a particular branch.",
        plans: [GitHub::Plan.business, GitHub::Plan.business_plus],
        feature_key: :protected_branches,
        docs_url: "#{GitHub.help_url}/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches",
        add_on: false,
        icon: :"git-branch",
        formatted_text: "protected branches",
      }
    when Rulesets then
      {
        name: "Rulesets",
        description: "Enforce how branches are merged by requiring reviews, or allowing specific contributors to work on a particular branch.",
        plans: [GitHub::Plan.business, GitHub::Plan.business_plus],
        feature_key: :rulesets,
        docs_url: "#{GitHub.help_url}/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets",
        add_on: false,
        icon: :"repo-push",
        formatted_text: "rulesets",
      }
    when CustomRepositoryRoles then
      {
        name: "Custom repository roles",
        description: "Get more granular control over the permissions you grant at the repository level by creating up to <%= number_to_words(RepositoryRole::BUSINESS_PLUS_CUSTOM_REPO_ROLE_LIMIT) %> custom roles.",
        plans: [GitHub::Plan.business_plus],
        feature_key: :custom_roles,
        docs_url: "#{GitHub.help_url}/organizations/managing-peoples-access-to-your-organization-with-roles/about-custom-repository-roles",
        add_on: false,
        icon: :"person-add",
        formatted_text: "custom repository roles",
      }
    when DraftPullRequests then
      {
        name: "Draft pull requests",
        description: "Allow collaborators to create pull requests that aren’t ready for review. When it’s ready, it can be marked as ready.",
        plans: [GitHub::Plan.business, GitHub::Plan.business_plus],
        feature_key: :draft_prs,
        docs_url: "#{GitHub.help_url}/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests#draft-pull-requests",
        add_on: false,
        icon: :"git-pull-request-draft",
        formatted_text: "draft pull requests",
      }
    when CopilotForBusiness then
      {
        name: Copilot.business_product_name,
        description: "GitHub Copilot uses the OpenAI large language models to suggest code and entire functions in real-time, right from your editor. You can set up a GitHub #{Copilot.business_product_name} subscription for your organization.",
        plans: [],
        feature_key: nil,
        docs_url: "#{GitHub.help_url}/copilot/overview-of-github-copilot/about-github-copilot-for-business",
        add_on: true,
        icon: :"copilot",
        formatted_text: Copilot.business_product_name,
      }
    end
  end

  # This method checks if a feature is already supported for the given organization or repository.
  #
  # @param repo [Repository] the repository that the requester is requesting the feature for
  # @param request_entity [Organization] the organization that the requester is requesting the feature for
  # @param business [Business] the business that the requester is requesting the feature for
  #
  # @return [Boolean] feature is supported or not.
  # @example
  #  Feature::ProtectedBranches.supported?(repo: repo, request_entity: request_entity) => true
  sig { params(repo: T.nilable(Repository), request_entity: T.nilable(Organization), business: T.nilable(Business)).returns(T::Boolean) }
  def supported?(repo: nil, request_entity: nil, business: nil)
    case self
    when ProtectedBranches, Rulesets
      !!repo && repo.supports_protected_branches?
    when CustomRepositoryRoles
      !!request_entity && request_entity.is_a?(Organization) && request_entity.custom_roles_supported?
    when DraftPullRequests
      !!repo && repo.plan_supports?(:draft_prs)
    when CopilotForBusiness
      if business.present?
        Copilot::Business.new(business).copilot_for_business_enabled?
      else
        !!request_entity && request_entity.is_a?(Organization) && Copilot::Organization.new(request_entity).has_copilot_for_business?
      end
    end
  end
end
