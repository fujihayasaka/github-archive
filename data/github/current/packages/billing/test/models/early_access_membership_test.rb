# typed: true
# frozen_string_literal: true

require "test_helper"

class EarlyAccessMembershipTest < GitHub::TestCase
  include GitHub::SurveyTestHelper
  TestClass = Struct.new(:id)

  setup do
    @user = create(:user)
  end

  context "validation" do
    test "requires member" do
      membership = EarlyAccessMembership.new(member: nil)
      refute membership.valid?
      refute_empty membership.errors[:member]
    end

    test "requires actor" do
      membership = EarlyAccessMembership.new(actor: nil)
      refute membership.valid?
      refute_empty membership.errors[:actor]
    end

    test "requires actor to be a user" do
      membership = EarlyAccessMembership.new(actor: create(:organization))
      refute membership.valid?
      refute_empty membership.errors[:actor]
    end

    test "requires actor to be an admin when member is an org" do
      membership = EarlyAccessMembership.new(actor: create(:user), member: create(:organization))
      refute membership.valid?
      refute_empty membership.errors[:actor]
    end

    test "any actor can enable for an org when it's for codespaces" do
      membership = EarlyAccessMembership.new(
        actor: create(:user),
        member: create(:organization),
        feature_slug: "workspaces",
        survey: build_survey("workspaces")
      )
      assert membership.valid?
    end


    test "requires actor to be an owner when member is an enterprise account" do
      membership = EarlyAccessMembership.new(actor: create(:user), member: create(:business))
      refute membership.valid?
      refute_empty membership.errors[:actor]
    end

    test "requires actor to be the same as member for users" do
      membership = EarlyAccessMembership.new(actor: create(:user), member: create(:user))
      refute membership.valid?
      refute_empty membership.errors[:actor]
    end

    test "permits organization to be used as a member" do
      user = create(:user)
      org = create(:organization, admin: user)
      membership = EarlyAccessMembership.new(
        actor: user,
        member: org,
        feature_slug: "projects_vnext",
        survey: create(:survey)
      )
      assert membership.valid?

      membership.save
      refute_nil EarlyAccessMembership.find_by(member: org)
    end

    test "requires survey" do
      membership = EarlyAccessMembership.new(survey: nil)
      refute membership.valid?
      refute_empty membership.errors[:survey]
    end

    test "requires feature_slug" do
      membership = EarlyAccessMembership.new(feature_slug: nil)
      refute membership.valid?
      refute_empty membership.errors[:feature_slug]
    end

    test "requires feature_slug to be one of the allowed values" do
      membership = EarlyAccessMembership.new(feature_slug: "illegalvalue")
      refute membership.valid?
      refute_empty membership.errors[:feature_slug]
    end

    test "does not require a member_class_name" do
      user = create(:user)
      assert EarlyAccessMembership.new(
        member: user,
        actor: user,
        feature_slug: "testing_only",
        survey: build_survey("testing_only")
      ).valid?
    end

    test "can update organization if actor is no longer an admin" do
      feature_slug = "testing_only"
      survey = build_survey(feature_slug)

      original_admin = create(:user)
      organization = create(:organization, admin: original_admin)

      membership = EarlyAccessMembership.create!(
        member: organization,
        actor: original_admin,
        survey_id: survey.id,
        feature_slug: feature_slug
      )

      new_admin = create(:user)
      organization.add_admin(new_admin)

      perform_enqueued_jobs(only: [RemoveOrgAdminJob, RemoveOrgMemberJob]) do
        organization.remove_member(original_admin)
      end

      refute organization.adminable_by?(original_admin)

      membership.update!(feature_enabled: true)
    end
  end

  context "callbacks" do
    test "it saves the member's class name to :member_class_name column on :create" do
      user = create(:user)
      org = create(:organization, admin: user)
      feature_slug = "testing_only"
      survey = build_survey(feature_slug)
      user_early_access_membership = EarlyAccessMembership.create!(
        member: user,
        actor: user,
        survey_id: survey.id,
        feature_slug: feature_slug
      )
      organization_early_access_membership = EarlyAccessMembership.create!(
        member: org,
        actor: user,
        survey_id: survey.id,
        feature_slug: feature_slug
      )

      assert_equal user_early_access_membership.member_class_name, "User"
      assert_equal organization_early_access_membership.member_class_name, "Organization"
    end

    test "it sets the member class correctly when the member is a memex project" do
      memex = create(:memex_project)
      feature_slug = "testing_only"
      survey = build_survey(feature_slug)
      user_early_access_membership = EarlyAccessMembership.create!(
        member: memex,
        actor: @user,
        survey_id: survey.id,
        feature_slug: feature_slug
      )

      assert_equal "MemexProject", user_early_access_membership.member_class_name
    end
  end

  context "#save_with_survey_answers" do
    test "saves survey answers" do
      survey     = build_survey("testing_only")
      question   = survey.questions.first
      membership = EarlyAccessMembership.new \
        member: @user,
        actor: @user,
        survey_id: survey.id,
        feature_slug: "testing_only"

      assert membership.save_with_survey_answers \
        [
          {
            question_id: question.id,
            choice_id: question.choices.first.id,
          },
        ]
      assert membership.valid?
    end

    test "saves multiple survey answers for features allowing multiple nominations" do
      feature_slug = "copilot_customization"
      survey = build_survey(feature_slug)
      question = survey.questions.first
      existing_membership = create(:early_access_membership, feature_slug: feature_slug, survey: survey)
      existing_survey_answer = create(:survey_answer, survey: survey, user: existing_membership.actor, question: question)

      # actor must be admin to nominate organization
      org = create(:organization)
      org.add_admin(existing_membership.actor)

      membership = EarlyAccessMembership.new \
        member: org,
        actor: existing_membership.actor,
        survey_id: survey.id,
        feature_slug: feature_slug

      assert_difference "SurveyAnswer.count", 1 do
        assert membership.save_with_survey_answers \
          [
            {
              question_id: question.id,
              choice_id: question.choices.first.id,
            },
          ]
        assert membership.valid?
      end
    end
  end

  context "#member_enabled?" do
    test "returns false for a user with no record for the feature" do
      user = User.new(id: 5)
      refute EarlyAccessMembership.member_enabled?("testing_only", user)
    end

    test "returns false if feature_enabled is not true" do
      user = User.new(id: 5)
      EarlyAccessMembership.create!(
        member: user,
        actor: user,
        feature_slug: "testing_only",
        survey: create(:survey),
      )

      refute EarlyAccessMembership.member_enabled?("testing_only", user)
    end

    test "returns true if feature_enabled is true" do
      user = User.new(id: 5)
      EarlyAccessMembership.create!(
        member: user,
        actor: user,
        feature_slug: "testing_only",
        feature_enabled: true,
        survey: create(:survey),
      )

      assert EarlyAccessMembership.member_enabled?("testing_only", user)
    end
  end
end
