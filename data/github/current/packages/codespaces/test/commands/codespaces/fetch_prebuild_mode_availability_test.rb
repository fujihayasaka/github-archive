
# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::FetchPrebuildModeAvailabilityTest < GitHub::TestCase
  include CodespacesPlanFixtures

  fixtures do
    disable_feature_flag(:codespaces_prebuilds_new_regions)
  end

  setup do
    @repo = create(:repository, from_example: :simple)
    @user = create(:user)
    @args = {
      repository: @repo,
      codespace_owner: @user,
      ref_name: "cr-line-endings",
      location: "CanadaCentral",
      vscs_target: "ppe"
    }
  end

  context "initialize" do
    test "sets default ref from ref_name if none provided" do
      availability = Codespaces::FetchPrebuildModeAvailability.new(**@args.merge(ref_name: nil))

      assert_equal @repo.default_branch, availability.send(:ref).name
    end

    test "uses default vscs_target if none provided" do
      availability = Codespaces::FetchPrebuildModeAvailability.new(**@args.merge(vscs_target: nil))

      assert_equal :production, availability.send(:vscs_target)
    end

    test "Is valid when only required values are passed" do
      availability = Codespaces::FetchPrebuildModeAvailability.new(
        repository: @repo,
        location: "EastUs",
        codespace_owner: @user,
      )
      assert_valid availability
    end
  end

  context "validations" do
    test "validates presence of repository" do
      error = assert_raises(ActiveModel::ValidationError) do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(repository: nil))
      end
      assert_includes error.message, "Repository can't be blank"
    end

    test "validates presence of branch_name" do
      error = assert_raises(ActiveModel::ValidationError) do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(ref_name: "invalid"))
      end
      assert_includes error.message, "Branch name could not be set from ref_name"
    end

    test "validates presence of oid" do
      error = assert_raises(ActiveModel::ValidationError) do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(ref_name: "invalid"))
      end
      assert_includes error.message, "Oid must be present or able to be inferred from ref_name"
    end

    test "validates presence of location" do
      error = assert_raises(ActiveModel::ValidationError) do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(location: nil))
      end
      assert_includes error.message, "Location can't be blank"
    end

    test "validates location is valid" do
      error = assert_raises(ActiveModel::ValidationError) do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(location: "FooBar", vscs_target: :ppe))
      end
      assert_includes error.message, "Location FooBar is not a valid location"
    end

    test "validates location is valid - ppe" do
      assert_nothing_raised do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(location: "SouthEastAsia", vscs_target: :ppe))
      end

      assert_nothing_raised do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(location: "CanadaCentral", vscs_target: :ppe))
      end
    end

    test "validates location is valid for new region" do
      assert_nothing_raised do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(location: "UkSouth",  vscs_target: :production))
      end
    end

    test "invalid if ref cannot be found" do
      error = assert_raises(ActiveModel::ValidationError) do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(ref_name: "not-a-ref"))
      end
      assert_includes error.message, "Ref could not be found"
    end

    test "ref must be a branch" do
      error = assert_raises(ActiveModel::ValidationError) do
        Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(ref_name: "v1"))
      end
      assert_includes error.message, "Ref must be a branch"
    end
  end

  context "#callbacks" do
    test "sets default branch name & oid if ref not provided" do
      availability = Codespaces::FetchPrebuildModeAvailability.new(**@args.merge(ref_name: nil))
      assert availability.valid?
      assert @repo.refs.find(@repo.default_branch).target_oid, availability.send(:oid)
      assert_equal @repo.default_branch, availability.send(:branch_name)
    end

    test "respects oid value passed in" do
      oid = @repo.refs.find("cr-line-endings").target_oid
      availability = Codespaces::FetchPrebuildModeAvailability.new(**@args.merge(oid: oid))
      assert oid, availability.send(:oid)
    end

  end

  context "#call" do
    test "returns available skus in the correct format, prebuild availability status enum" do
      create(:codespace_prebuild_configuration, repository: @repo)

      prebuild_availability = Codespaces::FetchPrebuildModeAvailability.call(**@args)
      expected = {
        basicLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        standardLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        basicLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
        premiumLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        xLargePremiumLinux: Codespaces::Prebuilds::AvailabilityStatus::IN_PROGRESS,
      }
      assert_equal(expected, prebuild_availability)
    end

    test "returns expected skus for fast path" do
      config = create(:codespace_prebuild_configuration, repository: @repo, fast_path_enabled: true)

      prebuild_availability = Codespaces::FetchPrebuildModeAvailability.call(**@args.merge(ref_name: "master"))
      expected = {
        basicLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        standardLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        basicLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
        premiumLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        xLargePremiumLinux: Codespaces::Prebuilds::AvailabilityStatus::IN_PROGRESS,
      }
      assert_equal(expected, prebuild_availability)
    end

    test "returns expected skus when config vscs target is nil" do
      config = create(:codespace_prebuild_configuration, repository: @repo, fast_path_enabled: true, vscs_target: nil)
      args = {
        repository: @repo,
        codespace_owner: @user,
        ref_name: "master",
        location: "EastUs",
        vscs_target: "production"
      }

      prebuild_availability = Codespaces::FetchPrebuildModeAvailability.call(**args)
      expected = {
        basicLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        standardLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        basicLinux: Codespaces::Prebuilds::AvailabilityStatus::READY,
        premiumLinux32gb: Codespaces::Prebuilds::AvailabilityStatus::READY,
        xLargePremiumLinux: Codespaces::Prebuilds::AvailabilityStatus::IN_PROGRESS,
      }
      assert_equal(expected, prebuild_availability)
    end

    test "returns expected value when no skus have prebuilds available" do
      create(:codespace_prebuild_configuration, repository: @repo)

      Codespaces::FetchPrebuildModeAvailability.any_instance.stubs(:fetch_available_skus_for_prebuild!).returns({
        "templateSkus": [],
        "poolSkus": [],
        "supportedSkus": [],
      })

      prebuild_availability = Codespaces::FetchPrebuildModeAvailability.call(**@args)

      assert_equal({}, prebuild_availability)
    end

    test "handles timeout error" do
      create(:codespace_prebuild_configuration, repository: @repo)

      Codespaces::FetchPrebuildModeAvailability.any_instance.stubs(:fetch_available_skus_for_prebuild!).raises(Faraday::TimeoutError.new("Boom!"))

      Failbot.expects(:report).with(
        instance_of(Faraday::TimeoutError),
        "catalog_service" => "github/codespaces",
        "gh.repo.id" => @repo.id,
        "gh.codespaces.vscs_target" => :ppe,
      )

      prebuild_availability = Codespaces::FetchPrebuildModeAvailability.call(**@args)

      assert_nil prebuild_availability
    end
  end

end unless GitHub.enterprise?
