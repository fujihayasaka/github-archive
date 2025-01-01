# typed: strict
# frozen_string_literal: true

require "test_helper"

class MemberFeatureRequest::FeatureTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = T.let(create(:user), T.nilable(User))
    @admin = T.let(create(:user), T.nilable(User))
    @repo = T.let(create(:repository), T.nilable(Repository))
    @organization = T.let(create(:organization, admin: @admin), T.nilable(Organization))

    T.must(@organization).add_member(@admin)
  end

  context "Feature" do
    test "enterprise_only? returns true for enterprise only features" do
      assert MemberFeatureRequest::Feature::CustomRepositoryRoles.enterprise_only?
    end

    test "enterprise_only? returns false for non enterprise only features" do
      refute MemberFeatureRequest::Feature::ProtectedBranches.enterprise_only?
      refute MemberFeatureRequest::Feature::DraftPullRequests.enterprise_only?
      refute MemberFeatureRequest::Feature::CopilotForBusiness.enterprise_only?
      refute MemberFeatureRequest::Feature::Rulesets.enterprise_only?
    end

    test "add_on? returns true for add-on features" do
      assert MemberFeatureRequest::Feature::CopilotForBusiness.add_on?
    end

    test "add_on? returns false for non add-on features" do
      refute MemberFeatureRequest::Feature::ProtectedBranches.add_on?
      refute MemberFeatureRequest::Feature::DraftPullRequests.add_on?
      refute MemberFeatureRequest::Feature::CustomRepositoryRoles.add_on?
      refute MemberFeatureRequest::Feature::Rulesets.add_on?
    end

    test "name returns the name of the feature" do
      assert_equal MemberFeatureRequest::Feature::ProtectedBranches.name, "Protected branches"
    end

    test "icon returns the icon of the feature" do
      assert_equal MemberFeatureRequest::Feature::ProtectedBranches.icon, :"git-branch"
    end

    test "docs_url returns the docs url of the feature" do
      assert_equal MemberFeatureRequest::Feature::ProtectedBranches.docs_url,
        "#{GitHub.help_url}/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches"
    end

    test "description returns the description of the feature" do
      assert_equal MemberFeatureRequest::Feature::ProtectedBranches.description,
        "Enforce how branches are merged by requiring reviews, or allowing specific contributors to work on a particular branch."
    end

    context "#supported?" do
      context "ProtectedBranches" do
        test "return false if no repo present" do
          refute MemberFeatureRequest::Feature::ProtectedBranches.supported?(repo: nil)
        end

        test "return false if repo does not support protected_branches" do
          private_repo = create(:private_repository, plan: "Free")

          refute MemberFeatureRequest::Feature::ProtectedBranches.supported?(repo: private_repo)
        end

        test "return true if repo already supports protected_branches" do
          assert MemberFeatureRequest::Feature::ProtectedBranches.supported?(repo: @repo)
        end
      end

      context "DraftPullRequests" do
        test "return false if repo is nil" do
          refute MemberFeatureRequest::Feature::DraftPullRequests.supported?(repo: nil)
        end

        test "return false if plan does not support draft_prs" do
          private_repo = create(:private_repository)

          refute MemberFeatureRequest::Feature::DraftPullRequests.supported?(repo: private_repo)
        end

        test "return true if repo plan supports draft_prs" do
          assert MemberFeatureRequest::Feature::DraftPullRequests.supported?(repo: @repo)
        end
      end

      context "CustomRepositoryRoles" do
        test "return false if org is nil" do
          refute MemberFeatureRequest::Feature::CustomRepositoryRoles.supported?(request_entity: nil)
        end

        test "return false if plan does not already support custom roles" do
          refute MemberFeatureRequest::Feature::CustomRepositoryRoles.supported?(request_entity: @organization)
        end

        test "return true if plan already supports custom roles" do
          business_plus_org = create(:business_plus_organization, admin: @user)

          assert MemberFeatureRequest::Feature::CustomRepositoryRoles.supported?(request_entity: business_plus_org)
        end
      end

      context "CopilotForBusiness" do
        test "return false if no org present" do
          refute MemberFeatureRequest::Feature::CopilotForBusiness.supported?(request_entity: nil)
        end

        test "return false if org does not have copilot for business" do
          refute MemberFeatureRequest::Feature::CopilotForBusiness.supported?(request_entity: @organization)
        end

        test "return true if org already has copilot for business" do
          copilot_enabled_org = create(:copilot_for_business_enabled_non_enterprise_organization, admin: @admin)

          assert MemberFeatureRequest::Feature::CopilotForBusiness.supported?(request_entity: copilot_enabled_org)
        end

        test "return true if enterprise already has copilot for business" do
          copilot_business = create(:copilot_business, :enterprise_plan)

          assert MemberFeatureRequest::Feature::CopilotForBusiness.supported?(business: copilot_business.business_object)
        end
      end

      context "Rulesets" do
        test "return false if no repo present" do
          refute MemberFeatureRequest::Feature::Rulesets.supported?(repo: nil)
        end

        test "return false if repo does not support rulesets" do
          private_repo = create(:private_repository, plan: "Free")

          refute MemberFeatureRequest::Feature::Rulesets.supported?(repo: private_repo)
        end

        test "return true if repo already supports rulesets" do
          assert MemberFeatureRequest::Feature::Rulesets.supported?(repo: @repo)
        end
      end

      context "when request entity is a business" do
        MemberFeatureRequest::Feature.values.each do |feature|
          test "#{feature} is not supported" do
            business_org = create(:business_organization, admin: @admin)

            refute feature.supported?(request_entity: business_org)
          end
        end
      end
    end
  end
end
