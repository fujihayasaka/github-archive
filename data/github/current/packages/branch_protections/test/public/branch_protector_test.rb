# typed: true
# frozen_string_literal: true

require "test_helper"

class BranchProtectorTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)

    @org = create(:organization, admin: @owner)
    @org_repo = create(:repository, owner: @org)

    @team = create(:team, organization: @org)
    @team.add_repository(@org_repo, :push)
    @team.add_member(@owner)

    @app = create(:integration)
    @org_repo_app_installation = make_integration_installation(
      integration: @app,
      repository: @org_repo,
      permissions: { "contents" => :write },
    )

    @ref_name = "main"
  end

  test "create branch protection" do
    branch_protection_data = {
      "required_status_checks" => {
        "strict" => true,
        "contexts" => %w[
          context1
          context2
        ]
      },
      "enforce_admins" => true,
      "required_pull_request_reviews" => {
          "dismiss_stale_reviews" => true,
          "require_code_owner_reviews" => true,
          "required_approving_review_count" => 2
      },
      "restrictions" => {
        "users" => [
          @owner.login
        ],
        "teams" => [
          @team.slug
        ],
        "apps" => [
          @app.slug
        ]
      },
      "required_linear_history" => true,
      "allow_force_pushes" => true,
      "allow_deletions" => true,
      "required_conversation_resolution" => true
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_equal true, result.success?
    assert_nil result.errors
    refute_nil result.protected_branch
  end

  test "update branch protection" do
    branch_protection_data = {
      "required_status_checks" => {
        "strict" => true,
        "contexts" => %w[
          context1
          context2
        ]
      },
      "enforce_admins" => T.let(true, T::Boolean),
      "required_pull_request_reviews" => {
          "dismiss_stale_reviews" => true,
          "require_code_owner_reviews" => true,
          "required_approving_review_count" => 2
      },
      "restrictions" => {
        "users" => [
          @owner.login
        ],
        "teams" => [
          @team.slug
        ],
        "apps" => [
          @app.slug
        ]
      },
      "required_linear_history" => true,
      "allow_force_pushes" => true,
      "allow_deletions" => true,
      "required_conversation_resolution" => true
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    branch_protection_data["enforce_admins"] = false
    result_updated = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result_updated.errors
    assert_equal false, result_updated.protected_branch.admin_enforced
  end

  test "honours users restrictions for org repo" do
    branch_protection_data = {
      "restrictions" => {
          "users" => [
            @owner.login
          ]
      }
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal @owner.login, result.protected_branch.authorized_actors[0].login
    assert_equal @owner.login, result.protected_branch.authorized_users[0].login
  end

  test "disallows users restrictions for user repo" do
    branch_protection_data = {
      "restrictions" => {
          "users" => [
            @owner.login
          ]
      }
    }.to_json

    result = BranchProtector.new(repository: @repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.protected_branch
    refute_nil result.errors
  end

  test "honours teams restrictions for org repo" do
    branch_protection_data = {
      "restrictions" => {
          "teams" => [
            @team.slug
          ]
      }
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal @team.slug, result.protected_branch.authorized_actors[0].slug
    assert_equal @team.slug, result.protected_branch.authorized_teams[0].slug
  end

  test "disallows teams restrictions for user repo" do
    branch_protection_data = {
      "restrictions" => {
          "teams" => [
            @team.slug
          ]
      }
    }

    result = BranchProtector.new(repository: @repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.protected_branch
    refute_nil result.errors
  end

  test "honours apps restrictions for org repo" do
    branch_protection_data = {
      "restrictions" => {
          "apps" => [
            @app.slug
          ]
      }
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal @app.slug, result.protected_branch.authorized_integrations[0].slug
  end

  test "disallows apps restrictions for user repo" do
    branch_protection_data = {
      "restrictions" => {
          "apps" => [
            @app.slug
          ]
      }
    }

    result = BranchProtector.new(repository: @repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.protected_branch
    refute_nil result.errors
  end

  test "disallows too many actors" do
    branch_protection_data = {
      "restrictions" => {
          "users" => []
      }
    }

    # Value of MAX_AUTHORIZED_ACTORS is 100
    101.times do
      user = create(:user)
      branch_protection_data["restrictions"]["users"].push(user.login)
    end

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.protected_branch
    refute_nil result.errors
  end

  test "honours strict status check" do
    branch_protection_data = {
      "required_status_checks" => {
        "strict" => true
      }
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal true, result.protected_branch.strict_required_status_checks_policy
  end

  test "honours enforce_admins" do
    branch_protection_data = {
      "enforce_admins" => true
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal true, result.protected_branch.strict_required_status_checks_policy
  end

  test "honours required_pull_request_reviews" do
    branch_protection_data = {
      "required_pull_request_reviews" => {
        "dismiss_stale_reviews" => true,
        "require_code_owner_reviews" => true,
        "require_last_push_approval" => true,
        "required_approving_review_count" => 2
      }
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal true, result.protected_branch.require_code_owner_review
    assert_equal true, result.protected_branch.require_last_push_approval
    assert_equal true, result.protected_branch.dismiss_stale_reviews_on_push
    assert_equal 2, result.protected_branch.required_approving_review_count
  end

  test "instruments required_approving_review_count on update" do
    events = subscribe "protected_branch.update_required_approving_review_count"
    branch_protection_data = {
      "required_pull_request_reviews" => {
        "required_approving_review_count" => 2
      }
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    branch_protection_data["required_pull_request_reviews"]["required_approving_review_count"] = 3
    result_updated = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result_updated.errors

    expected_payload = {
      protected_branch_id: result_updated.protected_branch.id,
      repo: @org_repo.nwo,
      repo_id: @org_repo.id,
      public_repo: @org_repo.public?,
      org_id: @org.id,
      org: @org.login,
      name: @ref_name,
      required_approving_review_count: 3,
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "honours required_linear_history" do
    branch_protection_data = {
      "required_linear_history" => true
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal "non_admins", result.protected_branch.linear_history_requirement_enforcement_level
  end

  test "honours allow_force_pushes" do
    branch_protection_data = {
      "allow_force_pushes" => true
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal "everyone", result.protected_branch.allow_force_pushes_enforcement_level
  end

  test "honours allow_deletions" do
    branch_protection_data = {
      "allow_deletions" => true
    }.to_json

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal "everyone", result.protected_branch.allow_deletions_enforcement_level
  end

  test "honours required_conversation_resolution" do
    branch_protection_data = {
      "required_conversation_resolution" => true
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal "non_admins", result.protected_branch.required_review_thread_resolution_enforcement_level
  end

  test "honours required_signatures when include_required_signatures is passed as true" do
    branch_protection_data = {
      "required_signatures" => true
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: true, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal "non_admins", result.protected_branch.signature_requirement_enforcement_level
  end

  test "ignores required_signatures when include_required_signatures is passed as false" do
    branch_protection_data = {
      "required_signatures" => true
    }

    result = BranchProtector.new(repository: @org_repo, actor: @owner, ref_name: @ref_name, data: branch_protection_data, include_required_signatures: false, entry_point: :test_case).protect_branch

    assert_nil result.errors
    assert_equal "off", result.protected_branch.signature_requirement_enforcement_level
  end

  context ".extract_required_status_checks" do
    test "looks up integration records" do
      status_checks = BranchProtector.extract_required_status_checks(
        @org_repo,
        {
          "checks" => [
            { "context" => "test", "app_id" => @app.id },
            { "context" => "other", "app_id" => nil },
          ],
        },
      )

      assert_equal(
        {
          checks: [
            { context: "test", source: :app, integration: @app },
            { context: "other", source: :app, integration: nil },
          ],
        },
        status_checks,
      )
    end

    test "accepts an app_id of -1 to indicate no app" do
      status_checks = BranchProtector.extract_required_status_checks(
        @org_repo,
        {
          "checks" => [
            { "context" => "test", "app_id" => -1 },
          ],
        },
      )

      assert_equal(
        {
          checks: [
            { context: "test", source: :any },
          ],
        },
        status_checks,
      )
    end

    test "required status checks are deduped for the checks requirement" do
      enable_feature_flag(:integration_specific_branch_protections, @org_repo)

      error = assert_raises(BranchProtector::DuplicatedContextError, "Context must be unique per branch protection.") do
        # Throws DuplicateContextError when context and app_id are duplicated
        BranchProtector.extract_required_status_checks(
          @org_repo,
          {
            "checks" => [
              { "context" => "test", "app_id" => @app.id },
              { "context" => "test", "app_id" => @app.id },
            ],
          }
        )
      end

      # Throws DuplicateContextError when context is duplicated but app_id is different
      error = assert_raises(BranchProtector::DuplicatedContextError, "Context must be unique per branch protection.") do
        BranchProtector.extract_required_status_checks(
          @org_repo,
          {
            "checks" => [
              { "context" => "test", "app_id" => @app.id },
              { "context" => "test", "app_id" => @app.id + 1 },
            ],
          }
        )
      end
    end
  end
end
