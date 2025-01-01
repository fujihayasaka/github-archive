# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationDisplayCommenterFullNameForRepoTest < GitHub::TestCase
  context ":private visibility" do
    GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name).each do |plan|
      test "returns true if the organization's plan supports display commenter full name and the setting is enabled for #{plan.name}" do
        user = create(:user)
        org = create(:organization, admin: user, plan: plan)
        org.enable_display_commenter_full_name(actor: user)
        assert org.display_commenter_full_name_for_repo?(visibility: :private, viewer: user)
      end

      test "returns false if the organization's setting is disabled for #{plan.name}" do
        user = create(:user)
        org = create(:organization, admin: user, plan: plan)

        org.disable_display_commenter_full_name(actor: user)
        refute org.display_commenter_full_name_for_repo?(visibility: :private, viewer: user)
      end
    end

    test "returns false if the organization's plan supports display commenter is false for unsupported plans" do
      unsupported_plans = GitHub::Plan.all_org_plans - GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name)
      unsupported_plans.each do |unsupported_plan|
        user = create(:user)
        org = create(:organization, admin: user, plan: unsupported_plan)
        org.enable_display_commenter_full_name(actor: user)
        refute org.display_commenter_full_name_for_repo?(visibility: :private, viewer: user)
      end
    end
  end

  context ":public visibility" do
    test "returns false if the organization's plan supports display commenter is false" do
      unsupported_plans = GitHub::Plan.all_org_plans - GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name)
      unsupported_plans.each do |unsupported_plan|
        user = create(:user)
        org = create(:organization, admin: user, plan: unsupported_plan)
        org.enable_display_commenter_full_name(actor: user)
        refute org.display_commenter_full_name_for_repo?(visibility: :public, viewer: user)
      end
    end

    test "returns false if the organization's setting is disabled" do
      GitHub::Plan.supported_org_plans_for_feature(feature: :display_commenter_full_name).each do |plan|
        user = create(:user)
        org = create(:organization, admin: user, plan: plan)
        org.disable_display_commenter_full_name(actor: user)
        refute org.display_commenter_full_name_for_repo?(visibility: :public, viewer: user)
      end
    end
  end

  if GitHub.enterprise?
    fixtures do
      @user = create :user
      @enterprise_org = create(:organization, plan: GitHub::Plan.enterprise, admin: @user)
    end

    context ":private visibility for enterprise on prem" do
      test "returns true if the organization's plan supports display commenter full name and the setting is enabled" do
        @enterprise_org.enable_display_commenter_full_name(actor: @user)
        assert @enterprise_org.display_commenter_full_name_for_repo?(visibility: :private, viewer: @user)
      end

      test "returns false if the organization's plan supports display commenter full name and the setting is disabled" do
        @enterprise_org.disable_display_commenter_full_name(actor: @user)
        refute @enterprise_org.display_commenter_full_name_for_repo?(visibility: :private, viewer: @user)
      end
    end

    context ":public visibility  for enterprise on prem" do
      test "returns true if the organization's plan supports display commenter full name and the setting is enabled" do
        @enterprise_org.enable_display_commenter_full_name(actor: @user)
        assert @enterprise_org.display_commenter_full_name_for_repo?(visibility: :public, viewer: @user)
      end

      test "returns false if the organization's plan supports display commenter full name and the setting is disabled" do
        @enterprise_org.disable_display_commenter_full_name(actor: @user)
        refute @enterprise_org.display_commenter_full_name_for_repo?(visibility: :public, viewer: @user)
      end
    end
  end
end
