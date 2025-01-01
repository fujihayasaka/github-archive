# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesSkusTest < GitHub::TestCase
  include CodespacesPlanFixtures
  SkuMock = Struct.new(:name)

  fixtures do
    @user = create(:user)
    @user_repo = create(:repository, owner: @user, from_example: :simple)
    @org = create(:codespaces_organization, plan: GitHub::Plan.business_plus, admin: @user)
    @org.add_member(@user)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

    @user_repo_codespace = create(:codespace, owner: @user, repository: @user_repo, sku_name: :prototypePremiumLinux)
    @user_org_repo_codespace = create(:codespace, owner: @user, repository: @org_repo, sku_name: :extremeLinux)
    @org_dev_codespace = create(:codespace, owner: @user, location: "WestEurope", vscs_target: :development, repository: @org_repo, sku_name: :premiumLinux)
    @policy_group = create(:policy_group, owner: @org)
    create(:policy_group_membership, policy_group: @policy_group, target: @org)

    GitHub.flipper[:codespaces_automated_testing].disable
  end

  context "#allowed_for_user?", skip_enterprise: true do
    test "returns false if the user doesn't have the relevant global feature flag(s)" do
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].disable(@user)
      sku = Codespaces::Skus.sku_by_name(:standardLinux)
      refute sku.allowed_for_user?(@user)
    end

    test "returns true if the user has the relevant global feature flag specifically" do
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].enable(@user)
      sku = Codespaces::Skus.sku_by_name(:standardLinux)
      assert sku.allowed_for_user?(@user)
    end

    test "returns false if the SKU is restricted by a Codespace dial and user is org" do
      sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)
      sku.stubs(:restricted_by_dial?).returns(true)
      refute sku.allowed_for_user?(@org)
    end

    test "returns true if the SKU is not restricted by a Codespace dial and user is org" do
      sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)
      sku.stubs(:restricted_by_dial?).returns(false)
      assert sku.allowed_for_user?(@org)
    end

    test "returns false if the SKU is restricted by a Codespace dial and user is user" do
      sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)
      sku.stubs(:restricted_by_dial?).returns(true)
      refute sku.allowed_for_user?(@user)
    end

    test "returns false if the SKU is restricted by a Codespace dial and user is user even with global flag" do
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].enable
      sku = Codespaces::Skus.sku_by_name(:standardLinux)
      sku.stubs(:restricted_by_dial?).returns(true)
      refute sku.allowed_for_user?(@user)
    end

    test "returns true if SKU isn't restricted by a Codespace dial and user is user" do
      sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)
      sku.stubs(:restricted_by_dial?).returns(false)
      assert sku.allowed_for_user?(@user)
    end

    test "returns true if the user is a test account" do
      sku = Codespaces::Skus.sku_by_name(:xLargePremiumLinux)
      GitHub.flipper[:codespaces_automated_testing].enable(@user)
      assert sku.allowed_for_user?(@user)
    end
  end

  context "#allowed_for_devcontainer?" do
    test "returns true when the SKU meets devcontainer requirements" do
      repo = create_repo_with_sku_requirements(cpus: 4, memory: "16gb", storage: "32gb")
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      sku = Codespaces::Skus.sku_by_name(:premiumLinux)
      assert sku.allowed_for_devcontainer?(dc)
    end

    test "returns false when the SKU doesn't meet devcontainer requirements" do
      repo = create_repo_with_sku_requirements(cpus: 4, memory: "16gb", storage: "32gb")
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)
      refute sku.allowed_for_devcontainer?(dc)
    end

    test "returns true if the devcontainer can't be read" do
      repo = create_repo_with_sku_requirements(cpus: 4, memory: "16gb", storage: "32gb")
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      dc.expects(:parse).raises(Codespaces::DevContainer::ReadError)
      sku = Codespaces::Skus.sku_by_name(:premiumLinux)
      assert sku.allowed_for_devcontainer?(dc)
    end
  end

  context "#restricted_by_dial?", skip_enterprise: true do
    context "for users" do
      test "raises error when unrecognized trust tier" do
        unknown_tier = TrustTiers::TierResult.new(7, "reason")
        sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)

        assert_raises Codespaces::Skus::Sku::InvalidTierError do
          sku.restricted_by_dial?(@user, unknown_tier)
        end
      end

      test "returns false when provided trust tier is TRUSTED" do
        trusted_tier = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason")
        sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)

        refute sku.restricted_by_dial?(@user, trusted_tier)
      end

      test "returns false when calculated trust tier has no corresponding dial" do
        trusted_tier = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason")
        Codespaces::Tier.expects(:for_user).with(@user).returns(trusted_tier)
        sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)

        refute sku.restricted_by_dial?(@user, nil)
      end

      test "returns true when the SKUs core count is above a dial's allowed value" do
        untrusted_tier = TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, nil)
        Codespaces::Dials::MaximumCoreCountPerCodespaceForUntrustedUser.any_instance.expects(:value).returns("4")
        sku = Codespaces::Skus.sku_by_name(:premiumLinux32gb)

        assert sku.restricted_by_dial?(@user, untrusted_tier)
      end
    end

    context "for orgs" do
      test "raises error when unrecognized trust tier" do
        unknown_tier = TrustTiers::TierResult.new(7, "reason")
        sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)

        assert_raises Codespaces::Skus::Sku::InvalidTierError do
          sku.restricted_by_dial?(@org, unknown_tier)
        end
      end

      test "returns false when trust tier is TRUSTED" do
        trusted_tier = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason")
        sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)

        refute sku.restricted_by_dial?(@org, trusted_tier)
      end

      test "returns false when calculated trust tier has no corresponding dial" do
        trusted_tier = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason")
        Codespaces::Tier.expects(:for_billable_owner).with(@org).returns(trusted_tier)
        sku = Codespaces::Skus.sku_by_name(:basicLinux32gb)

        refute sku.restricted_by_dial?(@org, nil)
      end

      test "returns true when the SKUs core count is above a dial's allowed value" do
        untrusted_tier = TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, nil)
        Codespaces::Dials::MaximumCoreCountPerCodespaceForUntrustedOrg.any_instance.expects(:value).returns("4")
        sku = Codespaces::Skus.sku_by_name(:premiumLinux32gb)

        assert sku.restricted_by_dial?(@org, untrusted_tier)
      end
    end
  end

  context "allowed_skus_for_new_codespace", skip_enterprise: true do
    test "filters to VSCS-allowed SKUs" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable(@user)
      sku_stubs = [:premiumLinux, :premiumLinux32gb, :madeUpSku].map do |name|
        stub = SkuMock.new(name: name)
        stub.stubs(:allowed_for_devcontainer?).returns(true)
        stub
      end
      Codespaces::Skus.stubs(:allowed_skus_with_owner_and_billable_owner).returns(sku_stubs)
      Codespaces::Skus.stubs(:allowed).returns(sku_stubs)

      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
      dev_skus = Codespaces::Skus.allowed_skus_for_new_codespace(repository_policy, vscs_target: :development, location: "WestUs2")
      prod_skus = Codespaces::Skus.allowed_skus_for_new_codespace(repository_policy, vscs_target: :production, location: "WestUs2")

      assert_equal [:premiumLinux, :premiumLinux32gb], dev_skus.map(&:name)
      assert_equal [:premiumLinux, :premiumLinux32gb], prod_skus.map(&:name)
    end

    test "filters by org policy" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable(@user)
      sku_stubs = [:premiumLinux, :premiumLinux32gb, :madeUpSku].map do |name|
        stub = SkuMock.new(name: name)
        stub.stubs(:allowed_for_devcontainer?).returns(true)
        stub
      end
      Codespaces::Skus.stubs(:allowed_skus_with_owner_and_billable_owner).returns(sku_stubs)
      Codespaces::Skus.stubs(:allowed).returns(sku_stubs)

      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @org_repo).sync
      dev_skus = Codespaces::Skus.allowed_skus_for_new_codespace(repository_policy, vscs_target: :development, location: "WestUs2")
      prod_skus = Codespaces::Skus.allowed_skus_for_new_codespace(repository_policy, vscs_target: :production, location: "WestUs2")

      assert_equal [:premiumLinux], dev_skus.map(&:name)
      assert_equal [:premiumLinux], prod_skus.map(&:name)
    end
  end

  context "allowed_skus_for_existing_codespace" do
    test "errors if the codespace isn't persisted" do
      assert_raises(ArgumentError) do
        Codespaces::Skus.allowed_skus_for_existing_codespace(Codespace.new)
      end
    end

    test "additionally includes a billable org's allowed SKUs" do
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@org)
      GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_32CORE_64GB_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable
      skus = Codespaces::Skus.allowed_skus_for_existing_codespace(@user_org_repo_codespace)
      refute_includes skus.map(&:name), :extremeLinux

      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].enable(@org)
      skus = Codespaces::Skus.allowed_skus_for_existing_codespace(@user_org_repo_codespace)
      assert_includes skus.map(&:name), :extremeLinux
    end

    test "filters by VSCS-allowed SKU transitions" do
      [
        Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG,
        Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG,
      ].each do |flag|
        GitHub.flipper[flag].enable(@user)
        GitHub.flipper[flag].enable(@org)
      end
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
      GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_32CORE_64GB_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].disable

      @org_dev_codespace.sku_name = :premiumLinux
      skus = Codespaces::Skus.allowed_skus_for_existing_codespace(@org_dev_codespace)
      # Should include SKUs listed as valid transitions, plus the current SKU
      assert_equal [:basicLinux,
                    :basicLinux32gb,
                    :largePremiumLinux,
                    :premiumLinux,
                    :standardLinux,
                    :standardLinux32gb], skus.map(&:name).sort
    end

    test "returns no SKUs if the current one is unsupported by VSCS" do
      @org_dev_codespace.stubs(:sku_name).returns("madeUpSku")
      skus = Codespaces::Skus.allowed_skus_for_existing_codespace(@org_dev_codespace)
      assert_equal [], skus
    end

    test "filters by org allowed SKUs" do
      user = create(:user)
      org = create(:codespaces_organization, plan: GitHub::Plan.business, admin: user)
      org_codespace = create(
        :codespace,
        owner: user,
        vscs_target: :development,
        repository: create(:private_repository, owner: org),
        sku_name: :basicLinux32gb,
      )
      policy_group = create(:policy_group, owner: org)
      create(:policy_group_membership, policy_group: policy_group, target: org)
      create(
        :policy_constraint,
        name: "codespaces.allowed_machine_types",
        policy_group: policy_group,
        allowed_values: [:basicLinux32gb, :standardLinux32gb]
      )
      skus = Codespaces::Skus.allowed_skus_for_existing_codespace(org_codespace)

      # Should include SKUs listed as valid transitions including the current codespace's SKU
      # (please note that these are stubbed and not indicative of production VSCS SKU allowed transistions)
      assert_equal [:basicLinux32gb, :standardLinux32gb], skus.map(&:name).sort
    end
  end

  context "allowed_skus_for_new_codespace_with_owner_and_billable_owner" do
    test "filters by org machine policy" do
      user = create(:user)
      org = create(:codespaces_organization, admin: user)
      org_repo = create(:private_repository, owner: org)
      policy_group = create(:policy_group, owner: org)
      create(:policy_group_membership, policy_group: policy_group, target: org)
      create(
        :policy_constraint,
        name: "codespaces.allowed_machine_types",
        policy_group: policy_group,
        allowed_values: [:basicLinux32gb]
      )
      skus = Codespaces::Skus.allowed_skus_for_new_codespace_with_owner_and_billable_owner(
        repository: org_repo,
        owner: user,
        location: "EastUs",
        ref: "main",
        billable_owner: org,
        vscs_target: :production
      )

      assert_equal [:basicLinux32gb], skus.map(&:name).sort
    end

    test "allows repo to be flagged for sku" do
      user = create(:user)
      org = create(:codespaces_organization, admin: user)
      org_repo = create(:private_repository, owner: org)
      GitHub.flipper[Codespaces::Skus::LINUX_32CORE_256GB_FEATURE_FLAG].enable(org_repo)

      skus = Codespaces::Skus.allowed_skus_for_new_codespace_with_owner_and_billable_owner(
        repository: org_repo,
        owner: user,
        location: "EastUs",
        ref: "main",
        billable_owner: org,
        vscs_target: :production
      )

      assert skus.map(&:name).include?(:xLargePremiumLinux256gb)
    end

    test "doesn't consider repo flag on public repository" do
      user = create(:user)
      org = create(:codespaces_organization, admin: user)
      org_repo = create(:public_repository, owner: org)
      GitHub.flipper[Codespaces::Skus::LINUX_32CORE_256GB_FEATURE_FLAG].enable(org_repo)

      skus = Codespaces::Skus.allowed_skus_for_new_codespace_with_owner_and_billable_owner(
        repository: org_repo,
        owner: user,
        location: "EastUs",
        ref: "main",
        billable_owner: org,
        vscs_target: :production
      )

      refute skus.map(&:name).include?(:xLargePremiumLinux256gb)
    end
  end

  context "allowed_for_new_codespace" do
    test "filters by org machine policy" do
      user = create(:user)
      org = create(:codespaces_organization, admin: user)
      org_repo = create(:private_repository, owner: org)
      policy_group = create(:policy_group, owner: org)
      create(:policy_group_membership, policy_group: policy_group, target: org)
      create(
        :policy_constraint,
        name: "codespaces.allowed_machine_types",
        policy_group: policy_group,
        allowed_values: [:basicLinux32gb]
      )
      skus = Codespaces::Skus.allowed_for_new_codespace(
        repository: org_repo,
        owner: user,
        location: "EastUs",
        ref: "main",
        billable_owner: org,
        vscs_target: :production
      )

      assert_equal [:basicLinux32gb], skus.map(&:name).sort
    end

    test "allows repo to be flagged for sku" do
      user = create(:user)
      org = create(:codespaces_organization, admin: user)
      org_repo = create(:private_repository, owner: org)
      GitHub.flipper[Codespaces::Skus::LINUX_32CORE_256GB_FEATURE_FLAG].enable(org_repo)

      skus = Codespaces::Skus.allowed_for_new_codespace(
        repository: org_repo,
        owner: user,
        location: "EastUs",
        ref: "main",
        billable_owner: org,
        vscs_target: :production
      )

      assert skus.map(&:name).include?(:xLargePremiumLinux256gb)
    end

    test "doesn't consider repo flag on public repository" do
      user = create(:user)
      org = create(:codespaces_organization, admin: user)
      org_repo = create(:public_repository, owner: org)
      GitHub.flipper[Codespaces::Skus::LINUX_32CORE_256GB_FEATURE_FLAG].enable(org_repo)

      skus = Codespaces::Skus.allowed_for_new_codespace(
        repository: org_repo,
        owner: user,
        location: "EastUs",
        ref: "main",
        billable_owner: org,
        vscs_target: :production
      )

      refute skus.map(&:name).include?(:xLargePremiumLinux256gb)
    end

    test "filters to VSCS-allowed SKUs" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable(@user)
      sku_stubs = [:premiumLinux, :premiumLinux32gb, :madeUpSku].map do |name|
        stub = SkuMock.new(name: name)
        stub.stubs(:allowed_for_devcontainer?).returns(true)
        stub
      end
      Codespaces::Skus.stubs(:allowed).returns(sku_stubs)

      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
      dev_skus = Codespaces::Skus.allowed_for_new_codespace(owner: @user, billable_owner: @user, repository: @user_repo, vscs_target: :development, location: "WestUs2")
      prod_skus = Codespaces::Skus.allowed_for_new_codespace(owner: @user, billable_owner: @user, repository: @user_repo, vscs_target: :production, location: "WestUs2")

      assert_equal [:premiumLinux, :premiumLinux32gb], dev_skus.map(&:name)
      assert_equal [:premiumLinux, :premiumLinux32gb], prod_skus.map(&:name)
    end

    test "filters by org policy" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable(@user)
      sku_stubs = [:premiumLinux, :premiumLinux32gb, :madeUpSku].map do |name|
        stub = SkuMock.new(name: name)
        stub.stubs(:allowed_for_devcontainer?).returns(true)
        stub
      end
      Codespaces::Skus.stubs(:allowed).returns(sku_stubs)

      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:premiumLinux], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)

      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @org_repo).sync
      dev_skus = Codespaces::Skus.allowed_for_new_codespace(owner: @user, billable_owner: @org, repository: @org_repo, vscs_target: :development, location: "WestUs2")
      prod_skus = Codespaces::Skus.allowed_for_new_codespace(owner: @user, billable_owner: @org, repository: @org_repo, vscs_target: :production, location: "WestUs2")

      assert_equal [:premiumLinux], dev_skus.map(&:name)
      assert_equal [:premiumLinux], prod_skus.map(&:name)
    end
  end

  context "allowed_for_existing_codespace" do
    test "errors if the codespace isn't persisted" do
      assert_raises(ArgumentError) do
        Codespaces::Skus.allowed_for_existing_codespace(Codespace.new)
      end
    end

    test "additionally includes a billable org's allowed SKUs" do
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@org)
      GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_32CORE_64GB_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable
      skus = Codespaces::Skus.allowed_for_existing_codespace(@user_org_repo_codespace)
      refute_includes skus.map(&:name), :extremeLinux

      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].enable(@org)
      skus = Codespaces::Skus.allowed_for_existing_codespace(@user_org_repo_codespace)
      assert_includes skus.map(&:name), :extremeLinux
    end

    test "filters by VSCS-allowed SKU transitions" do
      [
        Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG,
        Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG,
      ].each do |flag|
        GitHub.flipper[flag].enable(@user)
        GitHub.flipper[flag].enable(@org)
      end
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
      GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_32CORE_64GB_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].disable

      @org_dev_codespace.sku_name = :premiumLinux
      skus = Codespaces::Skus.allowed_for_existing_codespace(@org_dev_codespace)
      # Should include SKUs listed as valid transitions, plus the current SKU
      assert_equal [:basicLinux,
                    :basicLinux32gb,
                    :largePremiumLinux,
                    :premiumLinux,
                    :standardLinux,
                    :standardLinux32gb], skus.map(&:name).sort
    end

    test "returns no SKUs if the current one is unsupported by VSCS" do
      @org_dev_codespace.stubs(:sku_name).returns("madeUpSku")
      skus = Codespaces::Skus.allowed_for_existing_codespace(@org_dev_codespace)
      assert_equal [], skus
    end

    test "filters by org allowed SKUs" do
      user = create(:user)
      org = create(:codespaces_organization, plan: GitHub::Plan.business, admin: user)
      org_codespace = create(
        :codespace,
        owner: user,
        vscs_target: :development,
        repository: create(:private_repository, owner: org),
        sku_name: :basicLinux32gb,
      )
      policy_group = create(:policy_group, owner: org)
      create(:policy_group_membership, policy_group: policy_group, target: org)
      create(
        :policy_constraint,
        name: "codespaces.allowed_machine_types",
        policy_group: policy_group,
        allowed_values: [:basicLinux32gb, :standardLinux32gb]
      )
      skus = Codespaces::Skus.allowed_for_existing_codespace(org_codespace)

      # Should include SKUs listed as valid transitions including the current codespace's SKU
      # (please note that these are stubbed and not indicative of production VSCS SKU allowed transistions)
      assert_equal [:basicLinux32gb, :standardLinux32gb], skus.map(&:name).sort
    end
  end

  #  def self.allowed_for_display(codespace: nil, owner: nil, billable_owner:
  #  nil, repository: nil, location: nil, vscs_target: nil, vscs_target_url:
  #  nil, dev_container: nil, ref: nil, filter_by_policy: true,
  #  fetch_prebuild_availability: true)

  context "allowed_for_display", skip_enterprise: true do
    test "it filters to SKUs flagged for display and returns them in resource-ascending order" do
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
      GitHub.flipper[Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG].disable(@user)
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].disable(@user)
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
      skus = Codespaces::Skus.allowed_for_display(owner: @user, billable_owner: @user, repository: @user_repo, location: "EastUs", vscs_target: :production)
      refute_empty skus

      skus[1..-1].each_with_index do |sku, i|
        assert sku.gpus >= skus[1].gpus && (sku.cpus >= skus[i].cpus || sku.gpus > skus[1].gpus)
      end
    end

    context "with a pre-existing codespace" do
      test "always includes the codespace's current SKU" do
        GitHub.flipper[:codespaces_developer].disable
        GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
        skus = Codespaces::Skus.allowed_for_display(codespace: @user_repo_codespace)
        refute_includes skus.map(&:name), :extremeLinux

        @user_repo_codespace.update!(sku_name: :extremeLinux)
        skus = Codespaces::Skus.allowed_for_display(codespace: @user_repo_codespace)
        assert_includes skus.map(&:name), :extremeLinux
      end

      test "does not blow up if the codespace's sku_name is nil" do
        codespace = create(:codespace, owner: @user, repository: @user_repo)
        # Creation forces a valid SKU value but existing codespaces are not required
        # to have one and old ones do not in some cases.
        codespace.update(sku_name: nil)
        assert_nothing_raised do
          Codespaces::Skus.allowed_for_display(codespace: codespace)
        end
      end
    end

    context "without a pre-existing codespace", skip_enterprise: true do
      test "does not request prebuild availability if no skus are allowed" do
        create(:codespace_prebuild_configuration, repository: @user_repo)
        Codespaces::Skus.stubs(:allowed_for_new_codespace).returns([])
        skus = Codespaces::Skus.allowed_for_display(owner: @user, billable_owner: @user, repository: @user_repo, vscs_target: :development, location: "WestUs2")
        Codespaces::FetchPrebuildModeAvailability.expects(:call).never
        assert_equal [], skus
      end

      test "adds `none` prebuild value to skus when feature flag is on and prebuild is not available on skus" do
        create(:codespace_prebuild_configuration, repository: @user_repo)
        Codespaces::FetchPrebuildModeAvailability.any_instance.stubs(:perform).returns({
          templateSkus: [],
          poolSkus: [],
        })
        skus = Codespaces::Skus.allowed_for_display(owner: @user, billable_owner: @user, repository: @user_repo, vscs_target: :development, location: "WestUs2")
        refute_equal [], skus
        assert skus.map(&:prebuild_availability).all? { |sku| sku == "none" }
      end

      test "does not request prebuild availability if fetch_prebuild_availability is false" do
        GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable(@user)
        GitHub.flipper[Codespaces::Skus::LINUX_6CORE_128GB_NCV3_FEATURE_FLAG].disable(@user)
        create(:codespace_prebuild_configuration, repository: @user_repo)
        GitHub.flipper[Codespaces::Skus::LINUX_96CORE_64GB_GPU_FEATURE_FLAG].disable

        Codespaces::FetchPrebuildModeAvailability.expects(:call).never
        skus = Codespaces::Skus.allowed_for_display(owner: @user, billable_owner: @user, repository: @user_repo, vscs_target: :development, location: "WestUs2", fetch_prebuild_availability: false)
        refute_equal [], skus
      end

      test "adds prebuild values to skus when prebuild is available on skus, prebuild availability status enum" do
        GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
        GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable(@user)
        GitHub.flipper[Codespaces::Skus::LINUX_6CORE_128GB_NCV3_FEATURE_FLAG].disable(@user)
        GitHub.flipper[Codespaces::Skus::LINUX_96CORE_64GB_GPU_FEATURE_FLAG].disable(@user)
        create(:codespace_prebuild_configuration, repository: @user_repo)

        prebuild_skus = {
          basicLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          basicLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
          standardLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          standardLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
          premiumLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          premiumLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
          largePremiumLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          xLargePremiumLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          extremeLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::IN_PROGRESS, # Not allowed sku
        }

        Codespaces::FetchPrebuildModeAvailability.any_instance.stubs(:request_failed?).returns(false)
        Codespaces::FetchPrebuildModeAvailability.any_instance.stubs(perform: prebuild_skus)

        skus = Codespaces::Skus.allowed_for_display(owner: @user, billable_owner: @user, repository: @user_repo, vscs_target: :development, location: "WestUs2")

        refute_equal [], skus
        assert skus.map(&:prebuild_availability).all? { |sku| sku == "ready" }
      end
    end
  end

  context "allowed_skus_for_display", skip_enterprise: true do
    test "it filters to SKUs flagged for display and returns them in resource-ascending order" do
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
      GitHub.flipper[Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG].disable(@user)
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].disable(@user)
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
      skus = Codespaces::Skus.allowed_skus_for_display(repository_policy, location: "EastUs", vscs_target: :production)
      refute_empty skus

      skus[1..-1].each_with_index do |sku, i|
        assert sku.gpus >= skus[1].gpus && (sku.cpus >= skus[i].cpus || sku.gpus > skus[1].gpus)
      end
    end

    context "with a pre-existing codespace" do
      test "always includes the codespace's current SKU" do
        GitHub.flipper[:codespaces_developer].disable
        GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
        repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
        skus = Codespaces::Skus.allowed_skus_for_display(repository_policy, codespace: @user_repo_codespace)
        refute_includes skus.map(&:name), :extremeLinux

        @user_repo_codespace.update!(sku_name: :extremeLinux)
        repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
        skus = Codespaces::Skus.allowed_skus_for_display(repository_policy, codespace: @user_repo_codespace)
        assert_includes skus.map(&:name), :extremeLinux
      end

      test "does not blow up if the codespace's sku_name is nil" do
        codespace = create(:codespace, owner: @user, repository: @user_repo)
        # Creation forces a valid SKU value but existing codespaces are not required
        # to have one and old ones do not in some cases.
        codespace.update(sku_name: nil)
        assert_nothing_raised do
          repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
          Codespaces::Skus.allowed_skus_for_display(repository_policy, codespace: codespace)
        end
      end
    end

    context "without a pre-existing codespace", skip_enterprise: true do
      test "returns no SKUs if the user can't create a codespace for the repo" do
        repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, create(:private_repository)).sync
        assert_empty Codespaces::Skus.allowed_skus_for_display(repository_policy, location: "EastUs", vscs_target: :production)
      end

      test "does not request prebuild availability if no skus are allowed" do
        create(:codespace_prebuild_configuration, repository: @user_repo)
        repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
        Codespaces::Skus.stubs(:allowed_skus_for_new_codespace).returns([])
        skus = Codespaces::Skus.allowed_skus_for_display(repository_policy, vscs_target: :development, location: "WestUs2")
        Codespaces::FetchPrebuildModeAvailability.expects(:call).never
        assert_equal [], skus
      end

      test "adds `none` prebuild value to skus when feature flag is on and prebuild is not available on skus" do
        create(:codespace_prebuild_configuration, repository: @user_repo)
        repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
        Codespaces::FetchPrebuildModeAvailability.any_instance.stubs(:perform).returns({
          templateSkus: [],
          poolSkus: [],
        })
        skus = Codespaces::Skus.allowed_skus_for_display(repository_policy, vscs_target: :development, location: "WestUs2")
        refute_equal [], skus
        assert skus.map(&:prebuild_availability).all? { |sku| sku == "none" }
      end

      test "does not request prebuild availability if fetch_prebuild_availability is false" do
        GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable(@user)
        GitHub.flipper[Codespaces::Skus::LINUX_6CORE_128GB_NCV3_FEATURE_FLAG].disable(@user)
        create(:codespace_prebuild_configuration, repository: @user_repo)
        GitHub.flipper[Codespaces::Skus::LINUX_96CORE_64GB_GPU_FEATURE_FLAG].disable
        repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync

        Codespaces::FetchPrebuildModeAvailability.expects(:call).never
        skus = Codespaces::Skus.allowed_skus_for_display(repository_policy, vscs_target: :development, location: "WestUs2", fetch_prebuild_availability: false)
        refute_equal [], skus
      end

      test "adds prebuild values to skus when prebuild is available on skus, prebuild availability status enum" do
        GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
        GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable(@user)
        GitHub.flipper[Codespaces::Skus::LINUX_6CORE_128GB_NCV3_FEATURE_FLAG].disable(@user)
        GitHub.flipper[Codespaces::Skus::LINUX_96CORE_64GB_GPU_FEATURE_FLAG].disable(@user)
        create(:codespace_prebuild_configuration, repository: @user_repo)

        repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync

        prebuild_skus = {
          basicLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          basicLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
          standardLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          standardLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
          premiumLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          premiumLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
          largePremiumLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          xLargePremiumLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
          extremeLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::IN_PROGRESS, # Not allowed sku
        }

        Codespaces::FetchPrebuildModeAvailability.any_instance.stubs(:request_failed?).returns(false)
        Codespaces::FetchPrebuildModeAvailability.any_instance.stubs(perform: prebuild_skus)

        skus = Codespaces::Skus.allowed_skus_for_display(repository_policy, vscs_target: :development, location: "WestUs2")

        refute_equal [], skus
        assert skus.map(&:prebuild_availability).all? { |sku| sku == "ready" }
      end
    end
  end

  context "declarative skus", skip_enterprise: true do
    test "filters out insufficient skus" do
      repo = create_repo_with_sku_requirements(cpus: 4, memory: "16gb", storage: "32gb")
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, repo).sync
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      allowed_skus = if GitHub.flipper[:codespaces_allowed_skus_consolidation].enabled?
        Codespaces::Skus.allowed_for_display(owner: @user, billable_owner: @user, repository: repo, location: "EastUs", dev_container: dc)
      else
        Codespaces::Skus.allowed_skus_for_display(repository_policy, location: "EastUs", dev_container: dc)
      end
      refute_includes allowed_skus.map(&:name), :basicLinux32gb
    end

    test "no filtering without devcontainer" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable
      # Suppress 64 GB SKUs
      GitHub.flipper[Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].disable
      repo = create(:repository, owner: @org, from_example: :simple)
      repo.add_member(@user)
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, repo).sync
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      allowed_skus = if GitHub.flipper[:codespaces_allowed_skus_consolidation].enabled?
        Codespaces::Skus.allowed_for_display(owner: @user, billable_owner: repository_policy.billable_owner, repository: repo, location: "EastUs", dev_container: dc)
      else
        Codespaces::Skus.allowed_skus_for_display(repository_policy, location: "EastUs", dev_container: dc)
      end
      %i(basicLinux32gb standardLinux32gb premiumLinux32gb).each do |sku|
        assert_includes allowed_skus.map(&:name), sku
      end
    end

    test "no filtering without requirement values" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable
      # Suppress 64 GB SKUs
      GitHub.flipper[Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].disable
      repository = create(:repository, owner: @org, from_example: :simple)
      repository.add_member(@user)
      devcontainer_json = <<-JSON5
        {}
      JSON5

      repository.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repository.owner }, repository.owner) do |files|
        files.add(".devcontainer/devcontainer.json", devcontainer_json)
      end

      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, repository).sync

      dc = Codespaces::DevContainer.new(repository: repository, oid: repository.refs.find("master").target_oid)
      allowed_skus = if GitHub.flipper[:codespaces_allowed_skus_consolidation].enabled?
        Codespaces::Skus.allowed_for_display(owner: @user, billable_owner: repository_policy.billable_owner, repository: repository, location: "EastUs", dev_container: dc)
      else
        Codespaces::Skus.allowed_skus_for_display(repository_policy, location: "EastUs", dev_container: dc)
      end
      %i(basicLinux32gb standardLinux32gb premiumLinux32gb).each do |sku|
        assert_includes allowed_skus.map(&:name), sku
      end
    end
  end

  context "sku_availability_contexts_for_display", skip_enterprise: true do
    test "includes the codespace's current SKU even if disallowed" do
      GitHub.flipper[Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG].disable(@user)
      GitHub.flipper[:codespaces_developer].disable
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
      recs = Codespaces::Skus.sku_availability_contexts_for_display(repository_policy, codespace: @user_repo_codespace)
      refute_includes recs.map { |r| r.sku.name }, :extremeLinux

      @user_repo_codespace.update!(sku_name: :extremeLinux)
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync
      recs = Codespaces::Skus.sku_availability_contexts_for_display(repository_policy, codespace: @user_repo_codespace)
      assert_includes recs.map { |r| r.sku.name }, :extremeLinux
    end

    test "includes the codespace's current SKU even if devcontainer-restricted" do
      repo = create_repo_with_sku_requirements(storage: "64gb")
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, repo).sync
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      codespace = create(:codespace, owner: @user, repository: repo, sku_name: :basicLinux32gb)

      recs = Codespaces::Skus.sku_availability_contexts_for_display(repository_policy, codespace: codespace, dev_container: dc)
      assert_includes recs.map { |r| r.sku.name }, :basicLinux32gb

      rec = recs.find { |r| r.sku.name == :basicLinux32gb }
      refute rec.enabled # Below devcontainer requirements
    end

    test "includes the SKUs even if policy-restricted - with codespace" do
      GitHub.flipper[:codespaces_developer].disable
      user = create(:user)
      org = create(:codespaces_organization, plan: GitHub::Plan.business, admin: user)
      org_repo = create(:private_repository, owner: org)
      user_org_repo_codespace = create(:codespace, owner: user, repository: org_repo, sku_name: :prototypePremiumLinux)
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(user, org_repo).sync
      policy_group = create(:policy_group, owner: org)
      create(:policy_group_membership, policy_group: policy_group, target: org)
      create(
        :policy_constraint,
        name: "codespaces.allowed_machine_types",
        policy_group: policy_group,
        allowed_values: [:basicLinux32gb]
      )

      recs = Codespaces::Skus.sku_availability_contexts_for_display(repository_policy, codespace: user_org_repo_codespace)
      rec = recs.find { |r| r.sku.name == :prototypePremiumLinux }

      refute rec.enabled # Below policy requirements
      assert_equal Codespaces::Skus::AvailabilityContext::DOES_NOT_MEET_MACHINE_POLICY, rec.reason
    end

    test "includes the SKUs even if policy-restricted - without codespace" do
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @org_repo).sync

      create(:policy_constraint, policy_group: @policy_group, allowed_values: [:basicLinux32gb], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MACHINE_TYPES)
      recs = Codespaces::Skus.sku_availability_contexts_for_display(repository_policy, location: "EastUs", vscs_target: :production)

      rec = recs.find { |r| r.sku.name == :standardLinux32gb }
      refute rec.enabled # Below policy requirements
      assert_equal Codespaces::Skus::AvailabilityContext::DOES_NOT_MEET_MACHINE_POLICY, rec.reason
    end

    test "returns no SKU recs if the user can't create a codespace for the repo" do
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, create(:private_repository)).sync
      assert_empty Codespaces::Skus.sku_availability_contexts_for_display(repository_policy, location: "EastUs", vscs_target: :production)
    end

    test "does not request prebuild availability if fetch_prebuild_availability is false" do
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_repo).sync

      Codespaces::FetchPrebuildModeAvailability.expects(:call).never
      recs = Codespaces::Skus.sku_availability_contexts_for_display(repository_policy, location: "EastUs", vscs_target: :production, fetch_prebuild_availability: false)

      assert recs.length > 0
    end
  end

  context "::AvailabilityContext.for_skus" do
    test "recommended SKUs below devcontainer reqs are disabled" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable
      # Suppress 64 GB SKUs
      GitHub.flipper[Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].disable
      repo = create_repo_with_sku_requirements(memory: "64gb")
      skus = [
        Codespaces::Skus.sku_by_name(:basicLinux32gb),
        Codespaces::Skus.sku_by_name(:standardLinux32gb),
        Codespaces::Skus.sku_by_name(:premiumLinux32gb),
        Codespaces::Skus.sku_by_name(:extremeLinux),
      ]
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      sku_recs = Codespaces::Skus::AvailabilityContext.for_skus(skus, dev_container: dc)

      assert sku_recs.first.is_a?(Codespaces::Skus::AvailabilityContext)
      assert_equal :basicLinux32gb, sku_recs.first.sku.name
      refute sku_recs.first.enabled
      assert_equal Codespaces::Skus::AvailabilityContext::BELOW_DEVCONTAINER_REQUIREMENTS, sku_recs.first.reason
      refute sku_recs.first.default
    end

    test "recommended SKUs that are against machine policy are disabled" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable
      # Suppress 64 GB SKUs
      GitHub.flipper[Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG].disable
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].disable
      repo = create_repo_with_sku_requirements(memory: "8gb")
      skus = [
        Codespaces::Skus.sku_by_name(:basicLinux32gb),
        Codespaces::Skus.sku_by_name(:standardLinux32gb),
        Codespaces::Skus.sku_by_name(:premiumLinux32gb),
        Codespaces::Skus.sku_by_name(:extremeLinux),
      ]
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)

      sku_recs = Codespaces::Skus::AvailabilityContext.for_skus(skus, dev_container: dc, policy_allowed_skus: [:extremeLinux])

      assert sku_recs.first.is_a?(Codespaces::Skus::AvailabilityContext)
      assert_equal :basicLinux32gb, sku_recs.first.sku.name

      refute sku_recs.last.enabled
      assert_equal Codespaces::Skus::AvailabilityContext::DOES_NOT_MEET_MACHINE_POLICY, sku_recs.last.reason
    end

    test "preferred default is used when possible" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable
      repo = create_repo_with_sku_requirements(cpus: 8)
      skus = [
        Codespaces::Skus.sku_by_name(:basicLinux32gb),
        Codespaces::Skus.sku_by_name(:standardLinux32gb),
        Codespaces::Skus.sku_by_name(:premiumLinux32gb), # allowed and logical default
        Codespaces::Skus.sku_by_name(:extremeLinux), # allowed and will be preferred default
      ]
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      sku_recs = Codespaces::Skus::AvailabilityContext.for_skus(skus, dev_container: dc, preferred_default: :extremeLinux)
      default_recs = sku_recs.select(&:default)
      assert_equal 1, default_recs.size
      assert_equal :extremeLinux, default_recs.first.sku.name
    end

    test "preferred default is not used when not possible" do
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable
      repo = create_repo_with_sku_requirements(cpus: 8)
      skus = [
        Codespaces::Skus.sku_by_name(:basicLinux32gb),
        Codespaces::Skus.sku_by_name(:standardLinux32gb), # disallowed preferred default
        Codespaces::Skus.sku_by_name(:premiumLinux32gb), # allowed and logical default
      ]
      dc = Codespaces::DevContainer.new(repository: repo, oid: repo.refs.find("master").target_oid)
      sku_recs = Codespaces::Skus::AvailabilityContext.for_skus(skus, dev_container: dc, preferred_default: :standardLinux32gb)
      default_recs = sku_recs.select(&:default)
      assert_equal 1, default_recs.size
      assert_equal :premiumLinux32gb, default_recs.first.sku.name
    end
  end

  context "default_sku" do
    test "returns the expected default sku respecting devcontainer configuration" do
      # Enable a bunch of beefy SKUs
      GitHub.flipper[Codespaces::Skus::LINUX_8CORE_32GB_FEATURE_FLAG].enable(@user)
      GitHub.flipper[Codespaces::Skus::LINUX_2CORE_64GB_FEATURE_FLAG].enable(@user)
      GitHub.flipper[Codespaces::Skus::LINUX_4CORE_64GB_FEATURE_FLAG].enable(@user)
      repo = create_repo_with_sku_requirements(memory: "32gb")
      GitHub.flipper[Codespaces::Skus::LINUX_EXPERIMENTAL_FEATURE_FLAG].disable(repo)
      GitHub.flipper[Codespaces::Skus::LINUX_6CORE_128GB_NCV3_FEATURE_FLAG].disable(repo)
      default_sku = Codespaces::Skus.default_sku(
        repository: repo,
        owner: @org,
        location: "WestUs2",
      )
      assert_equal :premiumLinux, default_sku.name
    end
  end

  def create_repo_with_sku_requirements(cpus: 2, memory: "4gb", storage: "32gb")
    repository = create(:repository, owner: @org, from_example: :simple)
    repository.add_member(@user)
    devcontainer_json = <<-JSON5
      {
        "hostRequirements": {
          "cpus": #{cpus},
          "memory": "#{memory}",
          "storage": "#{storage}"
        }
      }
    JSON5

    repository.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repository.owner }, repository.owner) do |files|
      files.add(".devcontainer/devcontainer.json", devcontainer_json)
    end

    repository
  end
end unless GitHub.enterprise?
