# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::CreateTest < GitHub::TestCase
  include HydroTestHelpers
  include DogstatsTestHelpers
  include CodespacesPlanFixtures
  include GitHub::LoggerHelper

  def with_inline_repo_forking
    # This idea was taken from the `WithWorkingFork` module in another test.
    # Advice is a module in `test/test_helpers/advice.rb`
    advice_token = Advice.around(::Repository, :fork) do |_repo, callback|
      forked_repo = T.let(nil, T.nilable(Repository))
      status = T.let(nil, T.nilable(Symbol))
      errors = T.let(nil, T.nilable(T::Array[String]))

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        forked_repo, status, errors = callback.call
      end
      forked_repo.reload if forked_repo
      [forked_repo, status, errors]
    end
    yield if block_given?
    Advice.unaround(advice_token)
  end

  def create_repo_with_sku_requirements(cpus: 2, gpus: 0, memory: "4gb", storage: "32gb")
    repository = create(:repository, owner: @user_org, from_example: :simple)
    repository.add_member(@user)
    devcontainer_json = <<-JSON5
      {
        "hostRequirements": {
          "cpus": #{cpus},
          "gpus": #{gpus},
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

  def create_repo_with_devcontainer(devcontainer_json)
    repository = create(:repository, owner: @user_org, from_example: :simple)
    repository.add_member(@user)

    repository.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repository.owner }, repository.owner) do |files|
      files.add(".devcontainer/devcontainer.json", devcontainer_json)
    end

    repository
  end

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:credit_card_user, plan: GitHub::Plan.pro)
    @user.settings.set!(:trust_tier, TrustTiers::Tier::TRUSTED)

    create(:billing_budget, :codespaces, owner: @user, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)

    @must_fork_user = create(:credit_card_user, plan: GitHub::Plan.pro)
    create(:billing_budget, :codespaces, owner: @must_fork_user, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
    GitHub.flipper[:codespaces_offboarding_force_limit].disable
    GitHub.flipper[:codespaces_timeout_override_skip].disable
    @session = create(:user_session, user: @user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @master_head = @repo.heads.find_or_build("master")
    head_ref = @repo.heads.create("patch-1", @master_head.target, @user)
    head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
      files.add("file001", "foo")
    end
    @pull_request = create(:pull_request, repository: @repo, base_repository: @repo, head_repository: @repo,  user: @user, base_ref: "master", head_ref: "patch-1")
    @location = "EastUs"

    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)

    # Repo owned by another user that is forkable.
    @forkable_repo = create(:repository, from_example: :simple)
    with_inline_repo_forking do
      forked_repo, reason, errors = @forkable_repo.fork(forker: @user)
      ref = forked_repo.heads.find_or_build("master")
      ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
        files.add("file001", "foo")
      end
      @forked_pull = create(:pull_request,
        repository: @forkable_repo,
        base_repository: @forkable_repo,
        base_user: @forkable_repo.owner,
        base_ref: "master",
        head_repository: forked_repo,
        head_user: forked_repo.owner,
        head_ref: ref.name,
        user: @user
      )
    end

    @user_org = create(:codespaces_credit_card_organization, plan: GitHub::Plan.business, admin: @user)
    create(:billing_budget, :codespaces, owner: @user_org, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
    @user_org.add_member(@user)
    @user_org_public_repo = create(:repository, owner: @user_org, from_example: :simple)
    @user_org_public_repo.add_member(@user)
    Codespaces::OrgPolicy.grant_billing_permission!(@user, @user_org)

    @org_private_repo = create(:org_owned_private_repository, owner: @user_org)
    @org_private_repo.add_member(@user)
    example_repo :simple, @org_private_repo

    @older_commit = head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
      files.add("file001", "foo")
    end

    @newer_commit = head_ref.append_commit({ message: "more changes", committer: @user }, @user) do |files|
      files.add("file002", "bar")
    end

    emu = create(:emu)
    @business = emu.enterprise_managed_business

    @user.disable_feature(:codespaces_cwtp_no_limits)
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    reset_cache
    reset_monolith_redis_rate_limiter
    @provisioner = stub("Codespaces::ProvisionEnvironment", call: Codespaces::Environment.new)
    Codespaces::Secret.stubs(:assemble).returns([])
    # Prevent accidental future use of `ProvisionEnvironment` which will make network calls by default...
    Codespaces::ProvisionEnvironment.stubs(:call).raises(StandardError, "Please use the stubbed @provisioner in tests to avoid network calls.")
  end

  teardown_once do
    disable_cache_storage
  end

  context "validations", skip_enterprise: true do
    test "it prevents creation of codespaces when the repository is (legacy?) disabled" do
      GitHub.flipper[:codespaces_require_enabled_repository].enable
      disabled_repository = create(:repository, disabled_at: Time.now, from_example: :simple)

      create = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: disabled_repository.id,
          location: @location,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed: repository is disabled" do
        create.call
      end
    end

    test "it prevents creation of codespaces when the repository has a DMCA takedown" do
      GitHub.flipper[:codespaces_require_enabled_repository].enable
      disabled_repository = create(:repository, :dmca, from_example: :simple)

      create = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: disabled_repository.id,
          location: @location,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed: repository is disabled" do
        create.call
      end
    end

    test "it prevents creation of codespaces when plan owner is over usage limits" do
      Codespaces::Access::AllowedResult.any_instance.stubs(:allowed?).returns(false)
      Codespaces::Access::AllowedResult.any_instance.stubs(:disallowed_by_spending_limit?).returns(true)

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed: user #{@user.login} is at their spending limit" do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master"
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "it prevents creation of codespaces when the owner is spammy" do
      spammy_user = create(:user)
      spammy_user.mark_as_spammy

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed" do
        Codespaces::Create.call(
          attributes: {
            owner: spammy_user,
            repository_id: @repo.id,
            location: @location,
            ref: "master"
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "it prevents creation of codespaces when the repository owner is spammy" do
      spammy_user = create(:user)
      spammy_user.mark_as_spammy

      spammy_repo = create(:repository, owner: spammy_user, from_example: :simple)

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed" do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: spammy_repo.id,
            location: @location,
            ref: "master"
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "it prevents creation of codespaces when the billable owner is spammy" do
      spammy_user = create(:user)
      spammy_user.mark_as_spammy

      create = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      create.stubs(:billable_owner).returns(spammy_user)

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed" do
        create.call
      end
    end

    test "it doesn't raise NoMethodError if there's no billable_owner" do
      create = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      create.stubs(:billable_owner).returns(nil)

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Billable owner could not be determined for a new codespace" do
        create.call
      end
    end

    test "prevents internal region if codespaces_developer FF is disabled" do
      GitHub.flipper[:codespaces_developer].disable
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: Codespaces::Vscs.default_target)
      stamp.stubs(ga?: false)
      create = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: stamp.region.id,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Location is invalid" do
        create.call
      end
    end

    test "allows internal region if codespaces_developer FF is enabled" do
      GitHub.flipper[:codespaces_developer].enable
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: Codespaces::Vscs.default_target)
      stamp.stubs(ga?: false)
      create = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: stamp.region.id,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_nothing_raised do
        create.call
      end
    end

    test "prevents creation on a region where creates are disabled" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: Codespaces::Vscs.default_target)
      stamp.failover(creates: true, resumes: false)
      create = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: stamp.region.id,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Location is invalid" do
        create.call
      end
    end

    test "allows creation on a region where resumes are disabled but creates enabled" do
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: Codespaces::Vscs.default_target)
      stamp.failover(creates: false, resumes: true)
      create = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: stamp.region.id,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_nothing_raised do
        create.call
      end
    end

    test "if there is no sku passed, it is valid because the model adds a default" do
      assert_nothing_raised  do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    %w(sku_name machine).each do |field|
      test "if there is a standard #{field} passed for that user, it is valid" do
        assert_nothing_raised  do
          Codespaces::Create.call(
            attributes: {
              owner: @user,
              repository_id: @repo.id,
              location: @location,
              ref: "master",
              "#{field}": :standardLinux32gb,
            },
            user_session: @session,
            provisioner: @provisioner,
          )
        end
      end

      test "if there is a #{field} passed not enabled for that user, raises error" do
        GitHub.flipper[:codespaces_automated_testing].disable
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].disable(@user_org)
        assert_raises_with_message ActiveModel::ValidationError, Regexp.new("'extremeLinux' is not available") do
          Codespaces::Create.call(
            attributes: {
              owner: @user,
              repository_id: @user_org_public_repo.id,
              location: @location,
              ref: "master",
              "#{field}": :extremeLinux,
            },
            user_session: @session,
            provisioner: @provisioner,
          )
        end
      end

      test "if there is a feature-flagged #{field} passed that is enabled for that user, it is valid" do
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].enable(@user_org)

        assert_nothing_raised do
          Codespaces::Create.call(
            attributes: {
              owner: @user,
              repository_id: @user_org_public_repo.id,
              location: @location,
              ref: "master",
              "#{field}": :extremeLinux,
            },
            user_session: @session,
            provisioner: @provisioner,
          )
        end
      end

      test "if there is a feature-flagged #{field} passed that is enabled for the billable org, it is valid" do
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].disable(@user)
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].enable(@user_org)
        assert_nothing_raised do
          Codespaces::Create.call(
            attributes: {
              owner: @user,
              repository_id: @user_org_public_repo.id,
              location: @location,
              ref: "master",
              "#{field}": :extremeLinux,
            },
            user_session: @session,
            provisioner: @provisioner,
          )
        end
      end

      test "if there is a feature-flagged #{field} passed that is enabled for a non-billable org, raises error" do
        GitHub.flipper[:codespaces_automated_testing].disable
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].disable(@user)
        GitHub.flipper[::Codespaces::Skus::LEGACY_LINUX_32CORE_FEATURE_FLAG.to_sym].enable(@user_org)
        assert_raises_with_message ActiveModel::ValidationError, Regexp.new("'extremeLinux' is not available") do
          Codespaces::Create.call(
            attributes: {
              owner: @user,
              repository_id: @repo.id,
              location: @location,
              ref: "master",
              "#{field}": :extremeLinux,
            },
            user_session: @session,
            provisioner: @provisioner,
          )
        end
      end
    end

    test "it requires a ref or pull_request_id" do
      assert_raises_with_message ActiveModel::ValidationError, /Must specify a ref or pull request, but not both/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: nil,
            pull_request_id: nil
          },
          provisioner: @provisioner,
        )
      end
    end

    test "it disallows both a ref and pull_request_id" do
      assert_raises_with_message ActiveModel::ValidationError, /Must specify a ref or pull request, but not both/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            pull_request_id: @pull_request.id
          },
          provisioner: @provisioner,
        )
      end
    end

    test "it disallows target specification if the user does not have the flag enabled" do
      GitHub.flipper[:codespaces_developer].disable(@user)
      assert_raises_with_message ActiveModel::ValidationError, /Vscs target specified but owner is not authorized to use this feature/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            vscs_target: "development",
          },
          provisioner: @provisioner,
        )
      end
    end

    test "it disallows vscs_target_url if the user does not have the flag enabled" do
      GitHub.flipper[:codespaces_developer].disable(@user)
      assert_raises_with_message ActiveModel::ValidationError, /Vscs target url specified but owner is not authorized to use this feature/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            vscs_target_url: "https://vscstest.ngrok.io"
          },
          provisioner: @provisioner,
        )
      end
    end

    test "it disallows vscs_target_url if the target is not set to 'local'" do
      GitHub.flipper[:codespaces_developer].enable(@user)
      assert_raises_with_message ActiveModel::ValidationError, /Vscs target must be 'local' to specify a devstamp URL/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            vscs_target_url: "https://vscstest.ngrok.io",
            vscs_target: "development",
          },
          provisioner: @provisioner,
        )
      end
    end

    test "vscs_target_url be a valid URL if set" do
      assert_raises_with_message ActiveModel::ValidationError, /Vscs target url is not a valid URL/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            vscs_target_url: "foobar",
            vscs_target: "development",
          },
          provisioner: @provisioner,
        )
      end

      assert_raises_with_message ActiveModel::ValidationError, /Vscs target url is not a valid URL/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            vscs_target_url: "drbunix://::1",
            vscs_target: "development",
          },
          provisioner: @provisioner,
        )
      end
    end

    test "checks the disable_codespace_creation feature flag" do
      GitHub.flipper[:disable_codespace_creation].enable
      assert_raises_with_message ActiveModel::ValidationError, /Codespace creation is temporarily unavailable/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master"
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "owner must be a User" do
      organization = create(:organization, :with_codespaces_basic_tier_access)
      assert_raises_with_message ActiveModel::ValidationError, /Owner must be a user/ do
        Codespaces::Create.call(
          attributes: {
            owner: organization,
            repository_id: @repo.id,
            location: @location,
            pull_request_id: @pull_request.id
          },
          provisioner: @provisioner,
        )
      end
    end

    test "must only be readable by the codespace owner" do
      private_repo = create(:private_repository, owner: @user, from_example: :simple)
      user = create(:credit_card_user, plan: GitHub::Plan.pro)
      create(:billing_budget, :codespaces, owner: user, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
      session = create(:user_session, user: user)

      assert_raises_with_message ActiveModel::ValidationError, /Repository may not be used for a codespace/ do
        Codespaces::Create.call(
          attributes: {
            owner: user,
            repository_id: private_repo.id,
            location: @location,
            ref: "master"
          },
          user_session: session,
          provisioner: @provisioner,
        )
      end

      private_repo.add_member_without_validation_or_notifications(user, action: :read)

      assert_nothing_raised do
        Codespaces::Create.call(
          attributes: {
            owner: user,
            repository_id: private_repo.id,
            location: @location,
            ref: "master"
          },
          user_session: session,
          provisioner: @provisioner,
        )
      end
    end

    test "cannot create more than the per-user max", skip_enterprise: true do
      GitHub.flipper[:codespaces_per_user_sales_demo_limit].disable
      GitHub.flipper[:codespaces_automated_testing].disable

      rando = create(:credit_card_user, plan: GitHub::Plan.pro)
      create(:billing_budget, :codespaces, owner: rando, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
      rando_session = create(:user_session, user: rando)

      refute GitHub.flipper[:codespaces_developer].enabled?(rando)

      Codespaces::Policy.stub(:codespaces_limit, 1) do
        assert_nothing_raised do
          Codespaces::Create.call(
            attributes: {
              owner: rando,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: rando_session,
            provisioner: @provisioner,
          )
        end

        assert_raises_with_message ActiveModel::ValidationError, /Limit of 1 codespaces reached, delete one of your existing codespaces to create a new one/ do
          Codespaces::Create.call(
            attributes: {
              owner: rando,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: rando_session,
            provisioner: @provisioner,
          )
        end
      end
    end

    test "cannot create more than the per-user max when org policy is set", skip_enterprise: true do
      GitHub.flipper[:codespaces_per_user_sales_demo_limit].disable
      GitHub.flipper[:codespaces_automated_testing].disable

      rando = create(:credit_card_user, plan: GitHub::Plan.pro)
      rando_session = create(:user_session, user: rando)
      refute GitHub.flipper[:codespaces_developer].enabled?(rando)

      Codespaces::Policy.stub(:codespaces_limit, 2) do
        assert_nothing_raised do
          Codespaces::Create.call(
            attributes: {
              owner: rando,
              repository_id: @user_org_public_repo.id,
              location: @location,
              ref: "master"
            },
            user_session: rando_session,
            provisioner: @provisioner
          )
        end

        Codespaces::Query.any_instance.stubs(:at_limit?).returns(true)
        Codespaces::MaximumCreationPolicy.stubs(:get_applicable_creations_limit).returns(2)
        Codespaces::MaximumCreationPolicy.stubs(:get_limit_and_policy_owner).returns([2, @user_org])
        Codespaces::Create.any_instance.stubs(:billable_owner).returns(@user_org)
        Codespaces::Query.any_instance.stubs(:all_accessible_codespaces_for_org).returns(%w[codespace codespace2])

        assert_raises_with_message ActiveModel::ValidationError, /Limit of 2 codespaces based on a policy set by '#{@user_org}' is reached. Delete an existing codespace owned by '#{@user_org}' to create a new one/ do
          Codespaces::Create.call(
            attributes: {
              owner: rando,
              repository_id: @user_org_public_repo.id,
              location: @location,
              ref: "master",
            },
            user_session: rando_session,
            provisioner: @provisioner,
          )
        end
        assert_dogstats_increment(1, "codespaces.policy_enforcement.failed_create", tags: ["policy_constraint:codespaces.allowed_maximum_creations"])
      end
    end

    test "cannot create more than rate limit max of codespaces per minute when user is not a codespaces developer with FF on", skip_enterprise: true do
      GitHub.flipper[:codespaces_automated_testing].disable
      GitHub.flipper[:codespaces_bypass_rate_limiting].disable

      rando = create(:credit_card_user, plan: GitHub::Plan.pro)
      create(:billing_budget, :codespaces, owner: rando, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
      rando_session = create(:user_session, user: rando)

      GitHub.stub(:codespaces_per_minute_rate_limit, 1) do
        # Doesn't count older codespaces
        Timecop.freeze(65.minutes.ago) do
          Codespaces::Create.call(
            attributes: {
              owner: rando,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: rando_session,
            provisioner: @provisioner,
          )
        end

        Timecop.freeze do
          assert_nothing_raised do
            Codespaces::Create.call(
              attributes: {
                owner: rando,
                repository_id: @repo.id,
                location: @location,
                ref: "master"
              },
              user_session: rando_session,
              provisioner: @provisioner,
            )
          end

          assert_raises_with_message Codespaces::RateLimitError, /You have performed too many Codespaces actions too quickly. Please wait a few minutes and try again./ do
            Codespaces::Create.call(
              attributes: {
                owner: rando,
                repository_id: @repo.id,
                location: @location,
                ref: "master"
              },
              user_session: rando_session,
              provisioner: @provisioner,
            )
          end
          assert_dogstats_increment(1, "codespaces.rate_limited", tags: ["command:codespaces/create"])

          logger_output = {
            "Body" => "Codespace action blocked due to rate limiting.",
            "gh.catalog_service" => "github/codespaces",
            "gh.codespaces.command" => "codespaces/create",
            "gh.user.login" => rando.login,
          }
          assert_logged(**logger_output) do
            Codespaces::Create.call(
              attributes: {
                owner: rando,
                repository_id: @repo.id,
                location: @location,
                ref: "master"
              },
              user_session: rando_session,
              provisioner: @provisioner,
            ) rescue Codespaces::RateLimitError # Rescuing because we expect this failure
          end
        end
      end
    end

    test "user is not rate limited when codespaces developer with flag on" do
      rando = create(:credit_card_user, plan: GitHub::Plan.pro)
      create(:billing_budget, :codespaces, owner: rando, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
      rando_session = create(:user_session, user: rando)

      GitHub.flipper[:codespaces_automated_testing].enable(rando)
      GitHub.stub(:codespaces_per_minute_rate_limit, 1) do
        assert_nothing_raised do
          Codespaces::Create.call(
            attributes: {
              owner: rando,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: rando_session,
            provisioner: @provisioner,
          )
          Codespaces::Create.call(
            attributes: {
              owner: rando,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: rando_session,
            provisioner: @provisioner,
          )
          Codespaces::Create.call(
            attributes: {
              owner: rando,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: rando_session,
            provisioner: @provisioner,
          )
        end
      end
    end

    test "cannot create more than the codespaces_per_user_sales_demo_limit when user has that flag", skip_enterprise: true do
      GitHub.flipper[:codespaces_automated_testing].disable

      sales_demo_user = create(:credit_card_user, plan: GitHub::Plan.pro)
      create(:billing_budget, :codespaces, owner: sales_demo_user, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
      sales_demo_user_session = create(:user_session, user: sales_demo_user)

      GitHub.flipper[:codespaces_per_user_sales_demo_limit].enable(sales_demo_user)

      GitHub.stub(:codespaces_per_user_sales_demo_limit, 1) do
        assert_nothing_raised do
          Codespaces::Create.call(
            attributes: {
              owner: sales_demo_user,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: sales_demo_user_session,
            provisioner: @provisioner,
          )
        end

        assert_raises_with_message ActiveModel::ValidationError, /Limit of 1 codespaces reached, delete one of your existing codespaces to create a new one/ do
          Codespaces::Create.call(
            attributes: {
              owner: sales_demo_user,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: sales_demo_user_session,
            provisioner: @provisioner,
          )
        end
      end
    end

    test "it prevents creation of codespaces when retention_period_minutes is out of range" do
      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Retention period minutes must be between 0 and 43200" do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            retention_period_minutes: 31.days.in_minutes.to_i
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "prevents creation with a closed PR" do
      @pull_request.issue.close(@user)
      assert_raises_with_message ActiveModel::ValidationError, /Pull request is not allowed because it is closed/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id, # Base repo owned by @user
            location: @location,
            pull_request_id: @pull_request.id # PR on base repo
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "allows orgs to disable codespace creation" do
      @user_org.update_organization_codespaces_ownership_setting(
        Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @user) # need this to be set or will be USERS_AND_OUTSIDE_COLLABORATORS
      @user_org.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: @user)
      assert_raises_with_message ActiveModel::ValidationError, /Repository may not be used for a codespace/ do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @org_private_repo.id,
            location: @location,
            ref: @org_private_repo.default_branch
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "checks copilot workspace usage limits when providing a copilot_workspace_id" do
      @user.enable_feature(:copilot_workspace)
      create(:codespace_usage_record, :for_copilot_workspace, owner: @user, usage_seconds: Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true).value)
      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: Usage not allowed: user #{@user.login} has exhausted their allowed Copilot Workspace usage" do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            copilot_workspace_id: SecureRandom.hex(18)
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    context "Copilot Workspace limits" do
      context "total number of codespaces limit" do
        test "total number of codespaces created for Copilot Workspace is limited" do
          test_cw_id = SecureRandom.hex(18)
          @user.enable_feature(:copilot_workspace)

          Codespaces::Dials::MaximumTotalCopilotWorkspaceCodespacesForUser.update(1)
          create(:codespace, copilot_workspace_id: SecureRandom.hex(18), owner: @user)
          attributes = {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            copilot_workspace_id: test_cw_id,
          }
          assert_raises_with_message(ActiveModel::ValidationError, "Validation failed: Limit of Copilot Workspaces reached.") do
            Codespaces::Create.call(
              attributes:,
              user_session: @session,
              provisioner: @provisioner,
            )
          end
        end

        test "codespaces limits don't affect copilot workspace limits" do
          test_cw_id = SecureRandom.hex(18)
          @user.enable_feature(:copilot_workspace)
          Codespaces::Policy.stubs(:codespaces_limit).returns(1)
          create(:codespace, owner: @user)
          attributes = {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            copilot_workspace_id: test_cw_id,
          }
          assert_nothing_raised do
            Codespaces::Create.call(
              attributes:,
              user_session: @session,
              provisioner: @provisioner,
            )
          end
        end

        test "copilot workspace limits don't affect codespaces limits" do
          @user.enable_feature(:copilot_workspace)
          Codespaces::Dials::MaximumTotalCopilotWorkspaceCodespacesForUser.update(1)
          create(:codespace, copilot_workspace_id: SecureRandom.hex(18), owner: @user)
          attributes = {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          }
          assert_nothing_raised do
            Codespaces::Create.call(
              attributes:,
              user_session: @session,
              provisioner: @provisioner,
            )
          end
        end

        test "it blocks creation if the concurrency policy rejects it" do
          @user.enable_feature(:copilot_workspace)
          assert_raises Codespaces::CopilotWorkspaceConcurrencyLimitError do
            Codespaces::Create.new(
              attributes: {
                owner: @user,
                repository_id: @repo.id,
                location: @location,
                ref: "master",
                copilot_workspace_id: SecureRandom.hex(18),
              },
              user_session: @session,
              provisioner: @provisioner,
              concurrency_policy: FakeConcurrencyPolicy.new(allow: false),
            ).call
          end
        end

        test "copilot workspace limit only applies to specified codespace owner" do
          other_user = create(:user)
          other_user.enable_feature(:copilot_workspace)
          @user.enable_feature(:copilot_workspace)
          Codespaces::Dials::MaximumTotalCopilotWorkspaceCodespacesForUser.update(1)
          create(:codespace, copilot_workspace_id: SecureRandom.hex(18), owner: other_user)
          attributes = {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            copilot_workspace_id: SecureRandom.hex(18),
          }
          assert_nothing_raised do
            Codespaces::Create.call(
              attributes:,
              user_session: @session,
              provisioner: @provisioner,
            )
          end
        end

        test "copilot workspace limits don't apply if user has opt-out flag" do
          test_cw_id = SecureRandom.hex(18)
          @user.enable_feature(:copilot_workspace)
          @user.enable_feature(:codespaces_cwtp_no_limits)

          Codespaces::Dials::MaximumTotalCopilotWorkspaceCodespacesForUser.update(1)
          create(:codespace, copilot_workspace_id: SecureRandom.hex(18), owner: @user)
          attributes = {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            copilot_workspace_id: test_cw_id,
          }
          assert_nothing_raised do
            Codespaces::Create.call(
              attributes:,
              user_session: @session,
              provisioner: @provisioner,
            )
          end
        end
      end
    end
  end

  context "provisioning", skip_enterprise: true do
    test "returns github token" do

      @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      refute_nil result.github_token
    end

    test "uses seed plan vscs_target is set to local" do
      GitHub.flipper[:codespaces_developer].enable(@user)
      location = "WestUs2"
      @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: location,
          vscs_target: :local,
          vscs_target_url: "https://codespaces.servicebus.windows.net/monalisa",
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_equal result.codespace.plan.name, Codespaces::Plan.for(vscs_target: :local, location: location).name
    end

    test "preemptively schedules provisioning job in case things timeout" do
      @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

      assert_enqueued_with(job: CodespacesProvisionJob) do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master"
          },
          provisioner: @provisioner,
        )
      end
    end

    context "proxima plans" do
      test "uses plan if found" do
        on_multi_tenant_enterprise(tenant: @business) do
          location = "WestUs2"
          business_id = @business.id
          plan_name = "#{business_id}-location"
          @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))
          tenant_plan = create(:codespace_plan,
            location: location,
            vscs_target: :production,
            business_id: business_id,
            name: plan_name
          )

          result = Codespaces::Create.call(
            attributes: {
              owner: @user,
              repository_id: @repo.id,
              location: location,
              ref: "master"
            },
            user_session: @session,
            provisioner: @provisioner,
          )

          assert_equal result.codespace.plan.name, plan_name
        end
      end

      test "raises error if plan is not found" do
        on_multi_tenant_enterprise(tenant: @business) do
          location = "WestUs2"

          GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

          assert_raises(ActiveModel::ValidationError, "Location is invalid") do
            result = Codespaces::Create.call(
              attributes: {
                owner: @user,
                repository_id: @repo.id,
                location: location,
                ref: "master"
              },
              user_session: @session,
              provisioner: @provisioner,
            )
          end
        end
      end
    end

    context "default_idle_timeout" do
      test "uses org idle timeout if it is the most restrictive" do
        @policy_group_org = create(:policy_group, owner: @user_org, name: "all repos")
        create(:policy_group_membership, policy_group: @policy_group_org, target: @user_org)
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 30, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

        @user.update_codespace_default_idle_timeout(50, actor: @user)

        location = "WestUs2"
        @provisioner.expects(:call).with(instance_of(Codespace), has_entries(skip_find: true, environment_options: {
          autoShutdownDelayMinutes: 30, requestedIdleTimeoutMinutes: 40
        }))

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @user_org_public_repo.id,
            location: location,
            ref: "master"
          },
          environment_options: { requestedIdleTimeoutMinutes: 40 },
          user_session: @session,
          provisioner: @provisioner,
        )

        assert result.codespace
      end

      test "uses user's default idle timeout setting if no org policies override it" do
        @policy_group_org = create(:policy_group, owner: @user_org, name: "all repos")
        create(:policy_group_membership, policy_group: @policy_group_org, target: @user_org)
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

        @user.update_codespace_default_idle_timeout(50, actor: @user)

        location = "WestUs2"
        @provisioner.expects(:call).with(instance_of(Codespace), has_entries(skip_find: true, environment_options: {
          autoShutdownDelayMinutes: @user.codespace_default_idle_timeout
        }))

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @user_org_public_repo.id,
            location: location,
            ref: "master"
          },
          user_session: @session,
          provisioner: @provisioner,
        )

        assert result.codespace
      end

      test "uses API parameter if no org policies override it" do
        @policy_group_org = create(:policy_group, owner: @user_org, name: "all repos")
        create(:policy_group_membership, policy_group: @policy_group_org, target: @user_org)
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

        @user.update_codespace_default_idle_timeout(30, actor: @user)

        location = "WestUs2"
        @provisioner.expects(:call).with(instance_of(Codespace), has_entries(skip_find: true, environment_options: {
          autoShutdownDelayMinutes: 40, requestedIdleTimeoutMinutes: 40
        }))

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @user_org_public_repo.id,
            location: location,
            ref: "master"
          },
          environment_options: { requestedIdleTimeoutMinutes: 40 },
          user_session: @session,
          provisioner: @provisioner,
        )

        assert result.codespace
      end

      test "sets has_max_idle_timeout_policy_override key" do
        @policy_group_org = create(:policy_group, owner: @user_org, name: "all repos")
        create(:policy_group_membership, policy_group: @policy_group_org, target: @user_org)
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

        @user.update_codespace_default_idle_timeout(88, actor: @user)

        location = "WestUs2"

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @user_org_public_repo.id,
            location: location,
            ref: "master"
          },
          environment_options: { requestedIdleTimeoutMinutes: 120 },
          user_session: @session,
          provisioner: @provisioner,
        )
        assert result.codespace
        assert Codespaces::MaximumIdleTimeoutPolicy.has_override?(result.codespace.id)
      end

      test "removes has_max_idle_timeout_policy_override" do
        @policy_group_org = create(:policy_group, owner: @user_org, name: "all repos")
        create(:policy_group_membership, policy_group: @policy_group_org, target: @user_org)
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 240, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

        @user.update_codespace_default_idle_timeout(88, actor: @user)

        location = "WestUs2"

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @user_org_public_repo.id,
            location: location,
            ref: "master"
          },
          environment_options: { requestedIdleTimeoutMinutes: 120 },
          user_session: @session,
          provisioner: @provisioner,
        )
        assert result.codespace
        refute Codespaces::MaximumIdleTimeoutPolicy.has_override?(result.codespace.id)
      end

      test "uses vscs default" do
        location = "WestUs2"
        @provisioner.expects(:call).with(instance_of(Codespace), has_entries(skip_find: true, environment_options: {
          autoShutdownDelayMinutes: Codespaces::VscsClient::AUTO_SHUTDOWN_MINUTES
        }))

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @user_org_public_repo.id,
            location: location,
            ref: "master"
          },
          user_session: @session,
          provisioner: @provisioner,
        )

        assert result.codespace
      end

      test "overrides it for special repos" do
        @policy_group_org = create(:policy_group, owner: @user_org, name: "all repos")
        create(:policy_group_membership, policy_group: @policy_group_org, target: @user_org)
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

        @user.update_codespace_default_idle_timeout(30, actor: @user)

        location = "WestUs2"
        @provisioner.expects(:call).with(instance_of(Codespace), has_entries(skip_find: true, environment_options: {
          autoShutdownDelayMinutes: 9.hours.in_minutes.to_i, requestedIdleTimeoutMinutes: 40
        }))

        gh_org = Organization.find_by(login: "github")
        gh_repo = create(:repository, name: "github", owner: gh_org, from_example: :simple)
        @master_head = gh_repo.heads.find_or_build("master")
        head_ref = gh_repo.heads.create("patch-1", @master_head.target, @user)
        head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
          files.add("file001", "foo")
        end

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: gh_repo.id,
            location: location,
            ref: "master"
          },
          environment_options: { requestedIdleTimeoutMinutes: 40 },
          user_session: @session,
          provisioner: @provisioner,
        )

        assert result.codespace
      end

      test "skips override for special repos when FF enabled" do
        GitHub.flipper[:codespaces_timeout_override_skip].enable(@user)
        @policy_group_org = create(:policy_group, owner: @user_org, name: "all repos")
        create(:policy_group_membership, policy_group: @policy_group_org, target: @user_org)
        create(:policy_constraint, policy_group: @policy_group_org, maximum_value: 60, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

        @user.update_codespace_default_idle_timeout(30, actor: @user)

        location = "WestUs2"
        @provisioner.expects(:call).with(instance_of(Codespace), has_entries(skip_find: true, environment_options: {
          autoShutdownDelayMinutes: 40, requestedIdleTimeoutMinutes: 40
        }))

        gh_org = Organization.find_by(login: "github")
        gh_repo = create(:repository, name: "github", owner: gh_org, from_example: :simple)
        @master_head = gh_repo.heads.find_or_build("master")
        head_ref = gh_repo.heads.create("patch-1", @master_head.target, @user)
        head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
          files.add("file001", "foo")
        end

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: gh_repo.id,
            location: location,
            ref: "master"
          },
          environment_options: { requestedIdleTimeoutMinutes: 40 },
          user_session: @session,
          provisioner: @provisioner,
        )

        assert result.codespace
      end
    end

    test "runs asynchronously when there's a retryable error provisioning inline" do
      @provisioner.stubs(:call).raises(Codespaces::Client::TimeoutError)

      assert_enqueued_with(job: CodespacesProvisionJob) do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master"
          },
          provisioner: @provisioner,
        )
      end

      assert_dogstats_increment(1, "codespaces.create.synchronous.retryable_failure", tags: ["error:Codespaces::Client::TimeoutError"])
    end

    test "fails the codespace when there's a non-retryable error provisioning inline while still raising" do
      @provisioner.stubs(:call).raises(StandardError)

      assert_raises StandardError do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master"
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end

      assert T.must(Codespace.last).failed?
    end

    test "passes user session to async provisioning" do
      @provisioner.stubs(:call).raises(Codespaces::Client::TimeoutError)

      expected_args = ->(job_args) do
        kwargs = job_args.first
        refute_nil kwargs
        refute_nil kwargs[:codespace]
      end

      assert_enqueued_with(job: CodespacesProvisionJob, args: expected_args) do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master"
          },
          provisioner: @provisioner,
        )
      end
    end
  end

  test "Includes codespaces_automated_testing tag if data is for automated testing", skip_enterprise: true do
    @provisioner.stubs(:call).raises(Codespaces::Client::TimeoutError)
    GitHub.flipper[:codespaces_developer].enable(@user)

    assert_enqueued_with(job: CodespacesProvisionJob) do
      Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          vscs_target: "ppe",
          location: "CanadaCentral",
          ref: "master"
        },
        provisioner: @provisioner,
      )
    end

    assert_dogstats_increment(1, "codespaces.create.synchronous.retryable_failure", tags: ["error:Codespaces::Client::TimeoutError", "codespaces_automated_testing:true"])
  end

  test "includes is_copilot_workspace true if data is for copilot workspace", skip_enterprise: true do
    @provisioner.stubs(:call).raises(Codespaces::Client::TimeoutError)
    GitHub.flipper[:copilot_workspace].enable(@user)

    assert_enqueued_with(job: CodespacesProvisionJob) do
      Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: "EastUs",
          ref: "master",
          copilot_workspace_id: "123"
        },
        provisioner: @provisioner,
      )
    end

    assert_dogstats_increment(1, "codespaces.create.synchronous.retryable_failure", tags: ["error:Codespaces::Client::TimeoutError", "is_copilot_workspace:true"])
  end

  test "includes is_copilot_workspace false if data is not for copilot workspace", skip_enterprise: true do
    @provisioner.stubs(:call).raises(Codespaces::Client::TimeoutError)

    assert_enqueued_with(job: CodespacesProvisionJob) do
      Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: "EastUs",
          ref: "master",
        },
        provisioner: @provisioner,
      )
    end

    assert_dogstats_increment(1, "codespaces.create.synchronous.retryable_failure", tags: ["error:Codespaces::Client::TimeoutError", "is_copilot_workspace:false"])
  end

  context "creation from ref", skip_enterprise: true do
    test "returns the created codespace" do
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert result.codespace
      assert_equal "master", result.codespace.ref
      assert_equal @repo, result.codespace.repository
      assert_equal @location, result.codespace.location
    end

    test "sets the pull request ref if a singular PR for the specified ref can be found" do
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: @pull_request.head_ref
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert_equal @pull_request, result.codespace.pull_request
      assert result.codespace.pull_request.pull_request_sources.where(source: :codespace).exists?
    end

    test "dynamic PRs ignores PRs when head ref is default branch" do
      @pull_request.update(head_ref: @repo.default_branch)
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: @pull_request.head_ref
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      refute result.codespace.pull_request
    end

    test "dynamic PRs ignores other users' PRs with FF disabled" do
      GitHub.flipper[:codespaces_unscoped_find_pr].disable(@user)
      @pull_request.update(user: create(:user))
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: @pull_request.head_ref
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      refute result.codespace.pull_request
    end

    test "dynamic PRs associates other users' PRs with FF enabled" do
      GitHub.flipper[:codespaces_unscoped_find_pr].enable(@user)
      @pull_request.update(user: create(:user))
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: @pull_request.head_ref
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert_equal @pull_request, result.codespace.pull_request
    end

    test "sets the vscs_target_url on the codespace if the provided vscs_target is valid (local)" do
      GitHub.flipper[:codespaces_developer].enable(@user)

      devstamp_url = "https://codespaces.servicebus.windows.net/monalisa"
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: "WestUs2",
          ref: "master",
          vscs_target_url: devstamp_url,
          vscs_target: "local",
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert result.codespace
      assert_equal devstamp_url, result.codespace.vscs_target_url
    end
  end

  context "creation based on PR", skip_enterprise: true do
    test "it uses the PR head ref when given a PR" do
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id, # Base repo owned by @user
          location: @location,
          pull_request_id: @pull_request.id # PR on base repo
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert_equal @pull_request.head_ref, result.codespace.ref
    end

    test "raises when given an invalid PR id" do
      assert_raises ActiveRecord::RecordNotFound do
        Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id, # Base repo owned by @user
          location: @location,
          pull_request_id: 12345 # Bogus PR ID
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      end
    end

    test "creating a codespace against a PR that you own uses the right repo and ref" do
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @forked_pull.head_repository_id, # Base repo not owned by @user
          location: @location,
          pull_request_id: @forked_pull.id # PR from fork owned by @user
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert_equal @forked_pull.head_repository, result.codespace.repository
      assert_equal @forked_pull.head_ref, result.codespace.ref
    end

    test "creating a codespace against a PR with unpushable head repo still uses it" do
      with_inline_repo_forking do
        rando = create(:credit_card_user, plan: GitHub::Plan.pro)
        create(:billing_budget, :codespaces, owner: rando, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
        result = Codespaces::Create.call(
          attributes: {
            owner: rando,
            repository_id: @forked_pull.head_repository_id, # Base repo not owned by rando
            location: @location,
            pull_request_id: @forked_pull.id # PR from fork owned by @user
          },
          user_session: @session,
          provisioner: @provisioner,
        )
        assert_equal @forked_pull.head_repository_id, result.codespace.repository_id
      end
    end
  end

  context "default machine type and validation", skip_enterprise: true do
    test "when no machine is provided it finds an appropriate machine type" do
      repo = create_repo_with_sku_requirements(cpus: 4) # repo's devcontainer requires standardLinux32gb
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert_equal "standardLinux32gb", result.codespace.sku_name
    end

    test "when no machine is provided it corrects the region to handle the assigned SKU" do
      GitHub.flipper[:codespaces_linux_premium_gpu].enable

      repo = create_repo_with_sku_requirements(cpus: 0, gpus: 6) # repo's devcontainer requires GPUs, which are not available in UkSouth
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: repo.id,
          location: "UkSouth",
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert_equal "premiumLinuxGPU", result.codespace.sku_name
      assert_equal "WestEurope", result.codespace.location
    end

    test "when reassigning region based on SKU, it checks availability" do
      GitHub.flipper[:codespaces_linux_premium_gpu].enable
      GitHub.flipper[:codespaces_region_rejecting_creates_westeurope].enable
      GitHub.flipper[:codespaces_region_override_rejection_westeurope].disable

      repo = create_repo_with_sku_requirements(cpus: 0, gpus: 6) # repo's devcontainer requires GPUs, which are not available in UkSouth
      assert_raises Codespaces::Locations::Region::UnavailableError do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: repo.id,
            location: "UkSouth",
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "errors with a machine type that is below the minimums required by the repository is specified" do
      repo = create_repo_with_sku_requirements(cpus: 4) # repo's devcontainer requires standardLinux32gb
      assert_raises_with_message ActiveModel::ValidationError, Regexp.new("'basicLinux32gb' is not allowed for this repository") do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: repo.id,
            location: @location,
            ref: "master",
            machine: "basicLinux32gb" # Doesn't meet the minimum requirements of the devcontainer but we're not validating that
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "errors when no machine type is provided and no default can be found to satisify devcontainer" do
      repo = create_repo_with_sku_requirements(cpus: 1_024) # repo's devcontainer requires a SKU that doesn't exist
      assert_raises_with_message ActiveModel::ValidationError, Regexp.new(Codespaces::Skus::NO_VALID_MACHINE_TYPES_CATCHALL_MESSAGE) do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end

    test "displayname must be less than 48 characters" do
      assert_raises_with_message ActiveModel::ValidationError, Regexp.new("Display name must be 48 characters or less") do
        Codespaces::Create.call(
          attributes: {
            display_name: "a" * 49,
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end
  end

  context "base image validation", skip_enterprise: true do
    test "does not raise error when allowed by policy" do
      policy_group = create(:policy_group, owner: @user_org)
      create(:policy_constraint, policy_group: policy_group, allowed_values: ["ghcr.io/goodimage"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
      create(:policy_group_membership, policy_group: policy_group, target: @user_org)

      repo = create_repo_with_devcontainer({ image: "ghcr.io/goodimage" }.to_json)
      Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      )
    end

    test "errors with a base image policy that does not allow the image specified in the repository" do
      policy_group = create(:policy_group, owner: @user_org)
      create(:policy_constraint, policy_group: policy_group, allowed_values: ["ghcr.io/goodimage"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)
      create(:policy_group_membership, policy_group: policy_group, target: @user_org)

      repo = create_repo_with_devcontainer({ image: "badimage" }.to_json)
      assert_raises_with_message ActiveModel::ValidationError, Regexp.new("'badimage' is disallowed by policy set by your organization or enterprise administrator.") do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end
  end

  context "experimental feature support", skip_enterprise: true do
    test "passes information about enabled experimental features" do
      codespace = create(:codespace, :unprovisioned, owner: @user, repository: @repo)
      Codespaces::Tokens.stubs(:mint_github_token).returns("github-token")
      Codespace.stubs(:new).returns(codespace)
      # @provisioner.expects(:call).with(codespace, has_entry(environment_options: {
      #   experimentalFeatures: {localCredentialHelper: true}
      # }))
      # FIXME: see commented out line above.
      # experimentalFeatures was not part of the arguments, not sure why
      @provisioner.expects(:call).with(codespace, instance_of(Hash))

      Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )
    end

    test "does not pass experimental features unless enabled" do
      codespace = create(:codespace, :unprovisioned, owner: @user, repository: @repo)
      Codespaces::Tokens.stubs(:mint_github_token).returns("github-token")
      Codespace.stubs(:new).returns(codespace)
      @provisioner.expects(:call).with(codespace, has_key(:environment_options))

      Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master"
        },
        user_session: @session,
        provisioner: @provisioner,
      )
    end
  end

  context "metrics tags and logging", skip_enterprise: true do
    test "tracks when codespace is not created with prebuild" do
      Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      ).call

      assert_dogstats_distribution("codespaces/create.latency", tags: ["use_prebuild:false"])
    end

    test "tracks when codespace is created with prebuild" do
      create(:codespace_prebuild_configuration, repository: @repo)

      Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      ).call

      assert_dogstats_distribution("codespaces/create.latency", tags: ["use_prebuild:true"])
    end

    test "uses codespace's vscs_target if provided and user is developer" do
      GitHub.flipper[:codespaces_developer].enable(@user)

      codespace = build(:codespace, vscs_target: :development)
      cc = Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: "WestUs2",
          ref: "master",
          vscs_target: :development,
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      cc.result.codespace = codespace
      cc.call
      count = "codespaces/create.latency"
      assert_dogstats_distribution(count, tags: ["vscs_target:development"])
    end

    test "uses default vscs_target if not provided" do
      Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        provisioner: @provisioner,
        user_session: @session
      ).call
      count = "codespaces/create.latency"
      assert_dogstats_distribution(count, tags: ["vscs_target:#{Codespaces::Vscs.default_target}"])
    end

    test "tags automated users appropriately" do
      GitHub.flipper[:codespaces_automated_testing].enable(@user)
      Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      ).call
      count = "codespaces/create.latency"
      assert_dogstats_distribution(count, tags: ["codespaces_automated_testing:true"])
    end

    test "logs creation context" do
      expected_log_data = {
        "Body" => "codespace.created",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.billable_owner_login" => @user.login,
        "gh.codespaces.owner_login" => @user.login,
        "gh.repo.name_with_owner" => @repo.name_with_display_owner,
        "gh.codespaces.region" => @location,
      }

      assert_logged **expected_log_data do
        Codespaces::Create.new(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
        ).call
      end
    end
  end

  context "async operation tracking", skip_enterprise: true do
    test "is an accepted parameter" do
      operation = create(:codespaces_async_operation, operation: :create_codespace)
      assert_nothing_raised do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
          operation: operation,
        )
      end
    end

    test "is marked as started once the codespace is successfully created" do
      operation = create(:codespaces_async_operation, operation: :create_codespace)
      Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
        operation: operation,
      )
      assert operation.started?
    end

    test "is left unstarted if the codespace did not create" do
      operation = create(:codespaces_async_operation, operation: :create_codespace)
      # Note this will probably actually lead to the operation being ended in a future iteration on this...
      spammy_user = create(:user)
      spammy_user.mark_as_spammy

      assert_raises(ActiveModel::ValidationError) do
        Codespaces::Create.call(
          attributes: {
            owner: spammy_user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
          operation: operation,
        )
      end
      refute operation.started?
    end

    test "is marked as failed if a non-retryable error occurs" do
      operation = create(:codespaces_async_operation, operation: :create_codespace)
      @provisioner.stubs(:call).raises(StandardError)

      assert_raises(StandardError) do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
          operation: operation,
        )
      end
      assert operation.ended?
      assert_dogstats_increment(1, "codespaces.async_operations.ended", tags: ["operation:create_codespace", "state:failed"])
    end

    test "leaves the operation started when a retryable error occurs" do
      operation = create(:codespaces_async_operation, operation: :create_codespace)
      @provisioner.stubs(:call).raises(Codespaces::Client::TimeoutError)

      Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
        operation: operation,
      )

      refute operation.ended?
    end
  end

  context "concurrency limits", skip_enterprise: true do
    test "it allows creation if the concurrency policy allows it" do
      Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
        concurrency_policy: FakeConcurrencyPolicy.new(allow: true),
      ).call
    end

    test "it blocks creation if the concurrency policy rejects it" do
      assert_raises Codespaces::ConcurrencyLimitError do
        Codespaces::Create.new(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
          concurrency_policy: FakeConcurrencyPolicy.new(allow: false),
        ).call
      end
    end
  end

  context "the `codespace.created` metric", skip_enterprise: true do
    test "it emits for successful creates" do
      Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
        concurrency_policy: FakeConcurrencyPolicy.new(allow: true),
      ).call

      assert_dogstats_increment(1, "codespace.created")
    end

    test "tags storagev2 codespaces for internal users when enabled" do
      GitHub.flipper[:codespaces_developer].enable(@user)
      GitHub.flipper[:codespaces_force_storage_v2].enable(@user)

      Codespaces::Create.new(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      ).call

      assert_dogstats_distribution(1, "codespace.created.dist", tags: ["codespaces_use_storage_v2_internal:true"])
      assert_dogstats_distribution(1, "codespaces/create.success", tags: ["codespaces_use_storage_v2_internal:true"])
    end

    test "it does not emit when validation fails" do
      assert_raises ActiveModel::ValidationError do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: nil,
            pull_request_id: nil
          },
          provisioner: @provisioner,
          concurrency_policy: FakeConcurrencyPolicy.new(allow: true),
        )
      end

      assert_dogstats_increment(0, "codespace.created")
    end

    test "it does not emit when rate limited with feature flag on" do
      GitHub.flipper[:codespaces_automated_testing].disable
      GitHub.flipper[:codespaces_bypass_rate_limiting].disable
      user = create(:credit_card_user, plan: GitHub::Plan.pro)
      session = create(:user_session, user: user)
      create(:billing_budget, :codespaces, owner: user, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)

      GitHub.stub(:codespaces_per_minute_rate_limit, 0) do
        assert_raises Codespaces::RateLimitError do
          Codespaces::Create.call(
            attributes: {
              owner: user,
              repository_id: @repo.id,
              location: @location,
              ref: "master"
            },
            user_session: session,
            provisioner: @provisioner,
            concurrency_policy: FakeConcurrencyPolicy.new(allow: true),
          )
        end
      end

      assert_dogstats_increment(0, "codespace.created")
    end

    test "it does not emit when concurrency limited" do
      assert_raises Codespaces::ConcurrencyLimitError do
        Codespaces::Create.new(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
          },
          user_session: @session,
          provisioner: @provisioner,
          concurrency_policy: FakeConcurrencyPolicy.new(allow: false),
        ).call
      end

      assert_dogstats_increment(0, "codespace.created")
    end
  end

  context "retention_period_minutes" do
    test "sets retention_period_minutes" do
      @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

      # Sets to provided value
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
          retention_period_minutes: 60,
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert_equal 60, result.codespace.retention_period_minutes
    end

    test "sets retention_period_minutes defaults when none are provided" do
      @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_equal Codespace::MAX_RETENTION_PERIOD, result.codespace.retention_period_minutes
    end

    test "sets retention_period_minutes to user defined setting if set and none are provided" do
      @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

      @user.update_codespace_default_retention_period(1.day.in_minutes.to_i, actor: @user)
      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
        },
        user_session: @session,
        provisioner: @provisioner,
      )
      assert_equal @user.codespace_default_retention_period, result.codespace.retention_period_minutes
    end
    context "retention_period_minutes for Copilot Workspace codespaces" do
      test "sets retention_period_minutes to 1 day when a different number is provided" do
        @user.enable_feature :copilot_workspace
        @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

        # Sets to provided value
        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            copilot_workspace_id: "123",
            retention_period_minutes: 60,
          },
          user_session: @session,
          provisioner: @provisioner,
        )
        assert_equal 1440, result.codespace.retention_period_minutes
      end

      test "sets retention_period_minutes to 1 day when none is provided" do
        @user.enable_feature :copilot_workspace
        @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

        result = Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            copilot_workspace_id: "123",
          },
          user_session: @session,
          provisioner: @provisioner,
        )

        assert_equal 1440, result.codespace.retention_period_minutes
      end
    end
  end

  context "copilot workspace" do
    test "sets copilot_workspace_id if user has copilot_workspace feature enabled" do
      @user.enable_feature :copilot_workspace
      @provisioner.expects(:call).with(instance_of(Codespace), has_entry(skip_find: true))

      result = Codespaces::Create.call(
        attributes: {
          owner: @user,
          repository_id: @repo.id,
          location: @location,
          ref: "master",
          copilot_workspace_id: "123",
        },
        user_session: @session,
        provisioner: @provisioner,
      )

      assert_equal "123", result.codespace.copilot_workspace_id
    end

    test "raises if user does not have copilot_workspace feature enabled and passes a copilot_workspace_id" do
      @user.disable_feature :copilot_workspace
      assert_raises_with_message Codespaces::CopilotWorkspaceFeatureDisabledError, "User does not have access to the Copilot Workspace feature. Unable to create using copilot_workspace_id attribute." do
        Codespaces::Create.call(
          attributes: {
            owner: @user,
            repository_id: @repo.id,
            location: @location,
            ref: "master",
            copilot_workspace_id: "123",
          },
          user_session: @session,
          provisioner: @provisioner,
        )
      end
    end
  end

  class FakeConcurrencyPolicy
    def initialize(allow:)
      @allow = allow
    end

    def reserve_capacity(...)
      yield @allow
    end
  end
end unless GitHub.enterprise?
