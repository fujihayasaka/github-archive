# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryFeatureFlagsDependencyTest < GitHub::TestCase
  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @github = create(:organization, login: "github")
    @github.allow_private_repository_forking(actor: @github.admins.first)
    @member = @github.members.first
    @private_repository = create :private_repository, owner: @github
    @public_repository = create :repository, owner: @github, has_discussions: true, from_example: :tagsearch
    @public_repository.analyze_languages
    @other_business = if GitHub.single_business_environment?
      GitHub.global_business
    else
      create(:business)
    end
    @other_owner = create(:organization, business: @other_business)
    @other_repository = create(:repository, owner: @other_owner)

    example_repo :simple, @public_repository
    GitHub.flipper[:aleph_language_ruby].add
    GitHub.config.enable("git-lfs", @member)
  end

  context "#alephd_language_indexing_enabled?" do
    test "true when repo contains language supported by aleph and regular or darkship feature flag is enabled" do
      GitHub.flipper[:aleph_darkship_language_ruby].disable
      GitHub.flipper[:aleph_language_ruby].enable(@public_repository)
      assert @public_repository.alephd_language_indexing_enabled?

      GitHub.flipper[:aleph_language_ruby].disable
      GitHub.flipper[:aleph_darkship_language_ruby].enable(@public_repository)
      assert @public_repository.alephd_language_indexing_enabled?
    end

    test "false when repo contains language supported by aleph and regular and darkship feature flags are disabled" do
      # The @public_repository used in these tests contains blobs whose languages are analyzed as C, Go, JavaScript, and Ruby.
      # The GitHub all features build automatically enables feature flags that are not explicitly disabled, and is why we disable them here.
      GitHub.flipper[:aleph_language_c].disable
      GitHub.flipper[:aleph_darkship_language_c].disable
      GitHub.flipper[:aleph_language_go].disable
      GitHub.flipper[:aleph_darkship_language_go].disable
      GitHub.flipper[:aleph_language_javascript].disable
      GitHub.flipper[:aleph_darkship_language_javascript].disable
      GitHub.flipper[:aleph_language_ruby].disable
      GitHub.flipper[:aleph_darkship_language_ruby].disable

      refute @public_repository.alephd_language_indexing_enabled?
    end
  end

  context "#alephd_indexing_enabled?" do
    context "when repo contains languages supported by aleph indexing" do
      test "returns true when repo is included in a regular or darkship aleph language feature flag" do
        GitHub.flipper[:aleph_language_ruby].enable
        GitHub.flipper[:aleph_darkship_language_ruby].disable
        assert @public_repository.alephd_indexing_enabled?

        GitHub.flipper[:aleph_language_ruby].disable
        GitHub.flipper[:aleph_darkship_language_ruby].enable
        assert @public_repository.alephd_indexing_enabled?
      end

      test "returns false when repo is not included in a regular or darkship aleph language feature flag" do
        # The @public_repository used in these tests contains blobs whose languages are analyzed as C, Go, JavaScript, and Ruby.
        # The GitHub all features build automatically enables feature flags that are not explicitly disabled, and is why we disable them here.
        GitHub.flipper[:aleph_language_c].disable
        GitHub.flipper[:aleph_darkship_language_c].disable
        GitHub.flipper[:aleph_language_go].disable
        GitHub.flipper[:aleph_darkship_language_go].disable
        GitHub.flipper[:aleph_language_javascript].disable
        GitHub.flipper[:aleph_darkship_language_javascript].disable
        GitHub.flipper[:aleph_language_ruby].disable
        GitHub.flipper[:aleph_darkship_language_ruby].disable

        refute @public_repository.alephd_indexing_enabled?
      end
    end
  end

  context "#aleph_pull_request_create_feature_flags" do
    test "returns empty array for aleph-only feature flags for valid repo when feature disabled" do
      GitHub.flipper[:aleph_language_ruby].enable(@public_repository)
      assert @public_repository.alephd_language_indexing_enabled?

      SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns([])
      assert_equal [], @public_repository.pull_request_create_feature_flags
    end

    test "returns empty array aleph-only feature flags for invalid repo when feature enabled" do
      GitHub.flipper[:aleph_language_c].disable
      GitHub.flipper[:aleph_darkship_language_c].disable
      GitHub.flipper[:aleph_language_go].disable
      GitHub.flipper[:aleph_darkship_language_go].disable
      GitHub.flipper[:aleph_language_javascript].disable
      GitHub.flipper[:aleph_darkship_language_javascript].disable
      GitHub.flipper[:aleph_language_ruby].disable
      GitHub.flipper[:aleph_darkship_language_ruby].disable
      refute @public_repository.alephd_language_indexing_enabled?

      SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:pull_request_scanning_service_flags).returns([])
      assert_equal [], @public_repository.pull_request_create_feature_flags
    end

  end

  context "#eligible_for_blackbird_ingest?" do
    if GitHub.use_elastomer_code_search?
      test "is false when using elastomer code search" do
        refute @public_repository.eligible_for_blackbird_ingest?
      end
    else
      test "is true when not using elastomer code search" do
        assert @public_repository.eligible_for_blackbird_ingest?
      end
    end
  end

  context "git_lfs?" do
    test "true for private repositories with configured access" do
      assert @private_repository.git_lfs_enabled?
    end

    test "true for forks of private repositories with configured access" do
      fork, reason, errors = @private_repository.fork(forker: @member)
      assert fork, "unable to fork: #{reason}"

      assert fork.git_lfs_enabled?
    end

    test "true for public repositories with configured access" do
      assert @public_repository.git_lfs_enabled?
    end

    test "true for forks of public repositories with configured access" do
      fork, reason, errors = @public_repository.fork(forker: @member)
      assert fork, "unable to fork: #{reason} => #{errors.inspect}"

      assert fork.git_lfs_enabled?
    end

    test "true for other repositories" do
      assert @other_repository.git_lfs_enabled?
    end

    test "true for other forks" do
      fork, reason, errors = @other_repository.fork(forker: @member)
      assert fork, "unable to fork: #{reason} => #{errors.inspect}"

      assert fork.git_lfs_enabled?
    end
  end

  context "#post_receive_language_names" do
    test "when there is a repository with multiple languages to add" do
      assert_equal @public_repository.post_receive_language_names, %w[Go JavaScript C Ruby]
    end

    test "when there is a repository with no languages to add" do
      assert_equal @other_repository.post_receive_language_names, []
    end
  end

  context "#structured_issue_comment_templates_enabled?" do
    test "true when feature flag is enabled" do
      GitHub.flipper[:structured_issue_comment_templates].enable(@private_repository)
      assert_predicate @private_repository, :structured_issue_comment_templates_enabled?
    end

    test "false when feature flag is disabled" do
      GitHub.flipper[:structured_issue_comment_templates].disable(@private_repository)
      refute_predicate @private_repository, :structured_issue_comment_templates_enabled?
    end
  end

  context "scoped_feature_flag_enabled" do
    # (these use send() because async_scoped_feature_flag_enabled? is private)

    test "returns true when FF is enabled for repo and disabled for owner and business" do
      GitHub.flipper[:test_feature_flag].enable_actor(@other_repository)
      GitHub.flipper[:test_feature_flag].disable_actor(@other_owner)
      GitHub.flipper[:test_feature_flag].disable_actor(@other_business)

      assert @other_repository.send(:async_scoped_feature_flag_enabled?, :test_feature_flag).sync
    end

    test "returns true when FF is enabled for owner and disabled for repo and business" do
      GitHub.flipper[:test_feature_flag].disable_actor(@other_repository)
      GitHub.flipper[:test_feature_flag].enable_actor(@other_owner)
      GitHub.flipper[:test_feature_flag].disable_actor(@other_business)

      assert @other_repository.send(:async_scoped_feature_flag_enabled?, :test_feature_flag).sync
    end

    test "returns true when FF is enabled for business and disabled for repo and owner" do
      GitHub.flipper[:test_feature_flag].disable_actor(@other_repository)
      GitHub.flipper[:test_feature_flag].disable_actor(@other_owner)
      GitHub.flipper[:test_feature_flag].enable_actor(@other_business)

      assert @other_repository.send(:async_scoped_feature_flag_enabled?, :test_feature_flag).sync
    end

    test "returns false when FF is disabled for repo, owner and business" do
      GitHub.flipper[:test_feature_flag].disable_actor(@other_repository)
      GitHub.flipper[:test_feature_flag].disable_actor(@other_owner)
      GitHub.flipper[:test_feature_flag].disable_actor(@other_business)

      refute @other_repository.send(:async_scoped_feature_flag_enabled?, :test_feature_flag).sync
    end

    test "doesn't raise when repo has no owner" do
      # Sometimes repo.owner is nil, because we delete users immediately but keep repos around for 90 days after deletion
      @orphan_repository = create(:repository)
      GitHub.flipper[:test_feature_flag].disable_actor(@orphan_repository)

      assert_nothing_raised do
        refute @orphan_repository.send(:async_scoped_feature_flag_enabled?, :test_feature_flag).sync
      end
    end
  end

  context "#actor_tenant" do
    test "returns no tenant when not in Proxima mode" do
      if !TestEnv.test_in_multitenancy_mode?
        repo = create(:repository)
        result = repo.actor_tenant
        assert_nil result
      end
    end

    test "returns tenant info when in Proxima mode" do
      if TestEnv.test_in_multitenancy_mode?
        repo = create(:repository)
        result = repo.actor_tenant
        tenant = repo.owner.business
        assert_equal tenant.id, result.id
        assert_equal tenant.name, result.name
      end
    end

    test "returns no tenant info when in Proxima mode and owners business is missing" do
      if TestEnv.test_in_multitenancy_mode?
        user = User.create(login: "user-without-business-#{SecureRandom.hex(12)}")
        assert_nil user.business
        repo = Repository.create(name: "repo-#{SecureRandom.hex(12)}", owner: user)
        result = repo.actor_tenant
        assert_nil result
      end
    end
  end

  context "#flipper_actor_names" do
    test "from_flipper_actor_name" do
      repository = create :repository
      # assert that getting the repository from the flipper actor name returns the same repository
      assert_equal repository, Repository.from_flipper_actor_name(repository.flipper_actor_name)
      # assert that the flipper actor name has been overridden and is not the same as the flipper id
      refute_equal repository.flipper_id, repository.flipper_actor_name
      # assert that that flipper actor name is the name_with_display_owner
      assert_equal repository.name_with_display_owner, repository.flipper_actor_name
    end
  end

  context "#preview_features?" do
    test "returns false when preview_features is not enabled" do
      organization = Organization.create(login: "github")
      repo = Repository.instantiate("id" => 1122232, "owner_id" => organization.id, "source_id" => 1)
      repo.owner = organization
      repo.public = false
      GitHub.stubs(:preview_features_enabled?).returns(false)
      repo.feature_enabled?(:ff_name)
      assert_equal repo.preview_features?, false
    end

    test "returns false when initializing Repository with instantiate with no github owner" do
      repo = Repository.instantiate("id" => 1122232)
      repo.feature_enabled?(:ff_name)
      assert_equal repo.preview_features?, false
    end

    test "returns false when initializing Repository with instantiate does not have source_id" do
      organization = Organization.create(login: "github")
      repo = Repository.instantiate("owner_id" => organization.id)
      repo.feature_enabled?(:ff_name)
      assert_equal repo.preview_features?, false
    end

    test "returns true when initializing Repository with instantiate github owner and private" do
      organization = Organization.create(login: "github")
      repo = Repository.instantiate("id" => 1122232, "owner_id" => organization.id, "source_id" => 1)
      repo.owner = organization
      repo.public = false
      repo.feature_enabled?(:ff_name)
      assert_equal repo.preview_features?, true
    end

    test "returns false when initializing Repository with instantiate github owner and public" do
      organization = Organization.create(login: "github")
      repo = Repository.instantiate("id" => 1122232, "owner_id" => organization.id, "source_id" => 1)
      repo.owner = organization
      repo.public = true
      repo.feature_enabled?(:ff_name)
      assert_equal repo.preview_features?, false
    end

    test "returns false when initializing Repository with instantiate non-github owner and private" do
      organization = Organization.create(login: "notgithub")
      repo = Repository.instantiate("id" => 1122232, "owner_id" => organization.id, "source_id" => 1)
      repo.owner = organization
      repo.public = false
      repo.feature_enabled?(:ff_name)
      assert_equal repo.preview_features?, false
    end

    test "returns false when initializing Repository with instantiate non-github owner and public" do
      organization = Organization.create(login: "notgithub")
      repo = Repository.instantiate("id" => 1122232, "owner_id" => organization.id, "source_id" => 1)
      repo.owner = organization
      repo.public = true
      repo.feature_enabled?(:ff_name)
      assert_equal repo.preview_features?, false
    end
  end
end
