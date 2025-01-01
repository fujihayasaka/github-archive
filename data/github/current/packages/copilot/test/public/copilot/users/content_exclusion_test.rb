# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUserContentExclusion < GitHub::TestCase
  include CopilotTestHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
    @unaffiliated_user = create(:user)

    @org = create(:copilot_for_business_enabled_organization, login: "org")
    @org.add_member(@user, action: :admin)
    @business = @org.business
    @neighboring_org = create(:copilot_for_business_enabled_organization, business: @business, login: "neighboring-org")

    Copilot::Organization.new(@neighboring_org).seat_management_allow_all!
    Copilot::Organization.new(@org).seat_management_allow_all!

    # Repos
    @org_public_repo = create(:public_repository, owner: @org)
    @org_internal_repo = create(:internal_repository, owner: @org)
    @org_private_repo = create(:private_repository, owner: @org)

    @neighboring_public_repo = create(:public_repository, owner: @neighboring_org)
    @neighboring_internal_repo = create(:internal_repository, owner: @neighboring_org)
    @neighboring_private_repo = create(:private_repository, owner: @neighboring_org)
  end

  setup do
    @cfb_user = Copilot::User.new(@user)
    @cfi_user = Copilot::User.new(@unaffiliated_user)
  end

  def generate_config(entity)
    document = case entity
    when ::Repository
      "- /#{entity.id}/rule"
    else
      "\"*\": [\"/#{entity.id}/rule\"]"
    end

    create(
      :copilot_content_exclusion_configuration,
      entity.class.name.downcase.to_sym,
      resource: entity,
      document: document
    )
  end

  context "#copilot_content_exclusion_enabled?" do
    context "returns true" do
      test "when there is an org document" do
        generate_config(@org)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when there is an org with a document within the same enterprise" do
        generate_config(@neighboring_org)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when there is a public repo document" do
        generate_config(@org_public_repo)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when there is a internal repo document" do
        generate_config(@org_internal_repo)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when there is a private repo document" do
        generate_config(@org_private_repo)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when there is a public repo document in an org within the same enterprise" do
        generate_config(@neighboring_public_repo)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when there is a internal repo document in an org within the same enterprise" do
        generate_config(@neighboring_internal_repo)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when there is a private repo document in an org within the same enterprise" do
        generate_config(@neighboring_private_repo)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when there is an enterprise document" do
        generate_config(@business)
        @business.enable_feature(:content_exclusions_ga)
        assert @cfb_user.copilot_content_exclusion_enabled?
      end
    end

    context "returns false" do
      test "when there are no documents" do
        refute @cfb_user.copilot_content_exclusion_enabled?
      end

      test "when user is cfi" do
        generate_config(@org)
        refute @cfi_user.copilot_content_exclusion_enabled?
      end

      test "should be false when user is CFI despite being in an organization with an active document" do
        generate_config(@org)

        @org.add_member(@cfi_user.user_object)

        copilot_org = Copilot::Organization.new(@org)

        copilot_org.seat_management_selected_teams_and_users!(keep_assignments: false)
        Copilot::SeatManagement::Assigner.new(@org).assign(@cfb_user.user_object, @org.admins.first)

        refute @cfi_user.copilot_content_exclusion_enabled?
        assert @cfb_user.copilot_content_exclusion_enabled?
      end
    end
  end

  context "#content_exclusion_rules_for_repo_urls" do
    context "when accessing repos within the same org" do
      test "returns rules for public repos" do
        config = generate_config(@org_public_repo)
        results = @cfb_user.content_exclusion_rules_for_repo_urls([@org_public_repo.ssh_url_for_api])

        assert_equal 1, results.length
        assert_equal config, results.first.keys.first
      end

      test "returns rules for internal repos" do
        config = generate_config(@org_internal_repo)
        results = @cfb_user.content_exclusion_rules_for_repo_urls([@org_internal_repo.ssh_url_for_api])

        assert_equal 1, results.length
        assert_equal config, results.first.keys.first
      end

      test "returns rules for private repos" do
        config = generate_config(@org_private_repo)
        results = @cfb_user.content_exclusion_rules_for_repo_urls([@org_private_repo.ssh_url_for_api])

        assert_equal 1, results.length
        assert_equal config, results.first.keys.first
      end

      test "returns rules for repos correctly when org-level doc is present" do
        org_config = generate_config(@org)
        public_config = generate_config(@org_public_repo)
        internal_config = generate_config(@org_internal_repo)
        private_config = generate_config(@org_private_repo)

        results = @cfb_user.content_exclusion_rules_for_repo_urls([
          @org_public_repo.ssh_url_for_api,
          @org_internal_repo.ssh_url_for_api,
          @org_private_repo.ssh_url_for_api
        ])

        assert_equal 3, results.length

        assert_equal 2, results.first.length
        assert results.first.keys.include?(org_config)
        assert results.first.keys.include?(public_config)

        assert_equal 2, results.second.length
        assert results.second.keys.include?(org_config)
        assert results.second.keys.include?(internal_config)

        assert_equal 2, results.third.length
        assert results.third.keys.include?(org_config)
        assert results.third.keys.include?(private_config)
      end
    end

    context "when accessing repos within the same enterprise" do
      test "returns rules for public repos" do
        config = generate_config(@neighboring_public_repo)
        results = @cfb_user.content_exclusion_rules_for_repo_urls([@neighboring_public_repo.ssh_url_for_api])

        assert_equal 1, results.length
        assert_equal config, results.first.keys.first
      end

      test "returns rules for internal repos" do
        config = generate_config(@neighboring_internal_repo)
        results = @cfb_user.content_exclusion_rules_for_repo_urls([@neighboring_internal_repo.ssh_url_for_api])

        assert_equal 1, results.length
        assert_equal config, results.first.keys.first
      end

      test "doesn't return rules for private repos" do
        generate_config(@neighboring_private_repo)
        results = @cfb_user.content_exclusion_rules_for_repo_urls([@neighboring_private_repo.ssh_url_for_api])

        assert_equal [{}], results
      end

      test "returns rules for private repos if the user has access" do
        config = generate_config(@neighboring_private_repo)
        @neighboring_private_repo.add_member(@user)
        results = @cfb_user.content_exclusion_rules_for_repo_urls([@neighboring_private_repo.ssh_url_for_api])

        assert_equal 1, results.length
        assert_equal config, results.first.keys.first
      end

      test "returns rules for repos correctly when org-level doc is present" do
        org_config = generate_config(@neighboring_org)
        public_config = generate_config(@neighboring_public_repo)
        internal_config = generate_config(@neighboring_internal_repo)
        generate_config(@neighboring_private_repo)

        results = @cfb_user.content_exclusion_rules_for_repo_urls([
          @neighboring_public_repo.ssh_url_for_api,
          @neighboring_internal_repo.ssh_url_for_api,
          @neighboring_private_repo.ssh_url_for_api
        ])

        assert_equal 3, results.length

        assert_equal 1, results.first.length
        refute results.first.keys.include?(org_config)
        assert results.first.keys.include?(public_config)

        assert_equal 1, results.second.length
        refute results.second.keys.include?(org_config)
        assert results.second.keys.include?(internal_config)

        assert_equal 0, results.third.length
      end

      test "returns rules for repos correctly when org-level doc is present for the old flow" do
        @business.enable_feature(:content_exclusions_old_flow)
        org_config = generate_config(@neighboring_org)
        public_config = generate_config(@neighboring_public_repo)
        internal_config = generate_config(@neighboring_internal_repo)
        private_config = generate_config(@neighboring_private_repo)

        results = @cfb_user.content_exclusion_rules_for_repo_urls([
          @neighboring_public_repo.ssh_url_for_api,
          @neighboring_internal_repo.ssh_url_for_api,
          @neighboring_private_repo.ssh_url_for_api
        ])

        assert_equal 3, results.length

        assert_equal 2, results.first.length
        assert results.first.keys.include?(org_config)
        assert results.first.keys.include?(public_config)

        assert_equal 2, results.second.length
        assert results.second.keys.include?(org_config)
        assert results.second.keys.include?(internal_config)

        assert_equal 1, results.third.length
        assert results.third.keys.include?(org_config)
        refute results.third.keys.include?(private_config)
      end
    end
  end
end if GitHub.copilot_enabled?
