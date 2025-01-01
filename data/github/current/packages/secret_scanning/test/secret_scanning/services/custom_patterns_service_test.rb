# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPatternsServiceTest < GitHub::TestCase
  extend T::Sig

  ResponseMock = Struct.new(:data, :error)
  ResponseDataMock = Struct.new(:repository_ids, :pattern_matches, :error, :warning)

  fixtures do
    @user = create(:user)
    @non_creator = create(:paid_user)
    @business = create(:business, owners: [@user, @non_creator])
    @org = create(:organization, name: "github", admin: @user, business: @business)
    @tss_repo = create(:private_repository, owner: @org, name: "token-scanning-service", id: 45)
    @secret_scanning_repo = create(:private_repository, owner: @org, name: "secret-scanning", description: "the best repo", id: 46)
    @foo_repo = create(:private_repository, owner: @org, name: "foo-repo", id: 47)
    @bar_repo = create(:private_repository, owner: @org, name: "bar-repo", id: 48)

    @other_org = create(:organization, name: "hubgit", admin: @non_creator, business: @business)
    @other_repo = create(:private_repository, owner: @other_org, name: "other-repo", id: 200)
  end

  setup do
    @tss_client = GitHub::TokenScanning::Service::Client.new(@user)

    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
    else
      @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @business.set_advanced_security_seats_for_entity(actor: @user, seats: 10)
    end
  end

  test "#add_custom_pattern" do
    expression = "regex"
    display_name = "test"
    post_processing =  {
      start_delimiter: "a",
      end_delimiter: "b",
      must_match: "c",
      must_not_match: "d",
    }
    selector = {
      repo_scope: {
        repository_id: 1
      }
    }
    data = GitHub::Proto::SecretScanning::Api::V2::CreateCustomPatternResponse.new

    GitHub::TokenScanning::Service::Client.any_instance.expects(:create_custom_pattern).with(
      expression: expression,
      display_name: display_name,
      post_processing: post_processing,
      dry_run_repositories: nil,
      created_by_id: @user.id,
      repo_scope: {
        repository_id: 1
      },
    ).returns(Twirp::ClientResp[GitHub::Proto::SecretScanning::Api::V2::CreateCustomPatternResponse].new(
      data: data
    ))
    resp = service.add_custom_pattern(
      expression: expression,
      display_name: display_name,
      post_processing: post_processing,
      selector: selector,
    )
    assert resp
    assert_equal data, resp.data
  end


  context "#get_custom_patterns" do
    test "includes all states in the filter when omitted" do
      options = {}
      options[:selector] = {
        ids_selector: {
          ids: [1, 2]
        }
      }
      options[:filter] = {
        included_states: [:PUBLISHED, :DELETED, :DISABLED, :UNPUBLISHED]
      }
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_custom_patterns_paginated).with(options).returns(:data)
      assert service.get_custom_patterns_by_id([1, 2])
    end

    test "uses states passed in, and filters invalid states" do
      options = {}
      options[:selector] = {
        ids_selector: {
          ids: [1, 2]
        }
      }
      options[:filter] = {
        included_states: [:DISABLED, :UNPUBLISHED]
      }
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_custom_patterns_paginated).with(options).returns(:data)
      assert service.get_custom_patterns_by_id([1, 2], [:DISABLED, :UNPUBLISHED, :BAD_STATE])
    end
  end

  test "#get_custom_pattern" do
    options = {}
    options[:id] = 1
    options[:repo_selector] = {
      repository_id: 2
    }
    GitHub::TokenScanning::Service::Client.any_instance.expects(:get_custom_pattern).with(options).returns(Twirp::ClientResp[GitHub::Proto::SecretScanning::Api::V2::GetCustomPatternResponse].new(
      data: GitHub::Proto::SecretScanning::Api::V2::GetCustomPatternResponse.new
    ))
    assert service.get_custom_pattern(1, { repo_selector: { repository_id: 2 } })
  end

  test "#delete_custom_patterns" do
    to_delete = [{ id: 1, row_version: "1" }, { id: 2, row_version: 2 }]
    owner_id = 1
    owner_scope = GitHub::Proto::SecretScanning::Api::V3::OwnerScope::ORGANIZATION_SCOPE
    deleted_by_user_id = 1
    post_delete_action = :DELETE_ALERTS
    GitHub::TokenScanning::Service::Client.any_instance.expects(:delete_custom_patterns).with(
      to_delete: to_delete,
      owner_id: owner_id,
      owner_scope: owner_scope,
      deleted_by_id: deleted_by_user_id,
      post_delete_action: post_delete_action
    ).returns(Twirp::ClientResp[GitHub::Proto::SecretScanning::Api::V3::DeleteCustomPatternsResponse].new(
      data: GitHub::Proto::SecretScanning::Api::V3::DeleteCustomPatternsResponse.new
    ))
    assert service.delete_custom_patterns(patterns_with_row_versions: to_delete, owner_id: owner_id, owner_scope: owner_scope, deleted_by_user_id: deleted_by_user_id, post_delete_action: post_delete_action)
  end

  test "#delete_custom_pattern" do
    pattern_id = 1
    deleted_by_user_id = 1
    post_delete_action = :DELETE_ALERTS
    row_version = "1"
    owner_id = 1
    owner_scope = 1
    GitHub::TokenScanning::Service::Client.any_instance.expects(:delete_custom_pattern).with(
      id: pattern_id,
      deleted_by_id: deleted_by_user_id,
      post_delete_action: post_delete_action,
      row_version: row_version,
      owner_id: owner_id,
      owner_scope: owner_scope,
    ).returns(Twirp::ClientResp[Google::Protobuf::Empty].new(
      data: nil
    ))
    assert service.delete_custom_pattern(
      pattern_id: pattern_id,
      deleted_by_user_id: deleted_by_user_id,
      post_delete_action: post_delete_action,
      row_version: row_version,
      owner_id: owner_id,
      owner_scope: owner_scope,
    )
  end

  test "#publish_custom_pattern" do
    pattern_id = 1
    deleted_by_user_id = 1
    post_delete_action = :DELETE_ALERTS
    row_version = "1"
    owner_id = 1
    owner_scope = 1
    GitHub::TokenScanning::Service::Client.any_instance.expects(:publish_custom_pattern).with(
      id: pattern_id,
      row_version: row_version,
      updated_by_id: @user.id,
      owner_id: owner_id,
      owner_scope: owner_scope,
    ).returns(Twirp::ClientResp[Google::Protobuf::Empty].new(
      data: nil
    ))
    assert service.publish_custom_pattern(
      id: pattern_id,
      row_version: row_version,
      owner_id: owner_id,
      owner_scope: owner_scope,
    )
  end

  test "#update_custom_pattern" do
    pattern_id = 1
    expression = "regex"
    post_processing =  {
      start_delimiter: "a",
      end_delimiter: "b",
      must_match: "c",
      must_not_match: "d",
    }
    row_version = "1"
    owner_id = 1
    owner_scope = 1
    change_type = :DRY_RUN
    data = GitHub::Proto::SecretScanning::Api::V2::UpdateCustomPatternResponse.new
    GitHub::TokenScanning::Service::Client.any_instance.expects(:update_custom_pattern).with(
      id: pattern_id,
      expression: expression,
      post_processing: post_processing,
      change_type: change_type,
      dry_run_repositories: nil,
      row_version: row_version,
      updated_by_id: @user.id,
      owner_id: owner_id,
      owner_scope: owner_scope,
    ).returns(Twirp::ClientResp[GitHub::Proto::SecretScanning::Api::V2::UpdateCustomPatternResponse].new(
      data: data
    ))
    resp = service.update_custom_pattern(
      id: pattern_id,
      row_version: row_version,
      expression: expression,
      post_processing: post_processing,
      change_type: change_type,
      owner_id: owner_id,
      owner_scope: owner_scope,
    )
    assert resp
    assert_equal data, resp.data
  end

  context "#test_custom_pattern" do
    post_processing = {
      start_delimiter: nil,
      end_delimiter: nil,
      must_match: [],
      must_not_match: [],
    }

    svc_args = {
      display_name: "email",
      source_string: "foobar",
      expression: "regex",
      post_processing: post_processing,
    }

    test "succeeds" do
      result = { pattern_matches: [:data], error: nil, has_wildcard_warning: false }
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_pattern_matches).with(**svc_args).returns(res(pattern_matches: result[:pattern_matches], error: result[:error]))
      assert_equal result, service.test_custom_pattern(**svc_args)
    end

    test "returns empty pattern matches and error message if tss errors" do
      result = { pattern_matches: [], error: "this is an error", has_wildcard_warning: false }
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_pattern_matches).with(**svc_args).returns(res(error: result[:error]))
      assert_equal result, service.test_custom_pattern(**svc_args)
    end
  end

  context "#max_custom_patterns_created?" do
    test "returns if tss data nil" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_custom_patterns_total_count).returns(nil_data)
      refute service.max_allowed_custom_patterns_created?(:repo, 1)
    end
  end

  context "#valid_repositories" do
    test "org valid repositories" do
      # Repos 45 and 48 are defined in the fixtures
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: [45, 48, 100]))
      valid_repos = service.valid_repositories(@user.id, @org, [45, 48, 100])
      assert_equal [45, 48], T.must(valid_repos).sort
    end

    test "only returns user-owned repos for EMUs and for GHES" do
      @repo_without_org = create(:private_repository, owner: @user, name: "user-owned-repo", force_user_owned: true, id: 300)

      user_repo_expected = GitHub.enterprise? || TestEnv.test_with_all_emus?

      repo_ids = [300]
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: repo_ids))
      valid_repos = service.valid_repositories(@user.id, @business, repo_ids)
      if user_repo_expected
        assert_same_elements [300], T.must(valid_repos)
      else
        assert_same_elements [], T.must(valid_repos)
      end
    end

    test "business valid repos does not return repos in org without business" do
      @org_without_business = create(:organization, name: "org-without-business", admin: @user)
      @org_without_business_repos = create(:private_repository, owner: @org_without_business, name: "lonely-repo", id: 400)

      repo_ids = [400]
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: repo_ids))
      valid_repos = service.valid_repositories(@user.id, @business, repo_ids)
      assert_equal [], T.must(valid_repos).sort
    end

    test "business valid repos returned correctly" do
      # Repos 45 and 48 are defined in the fixtures, 100 is deliberately used because it does not exist
      repo_ids = [45, 48, 100]
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: repo_ids))
      valid_repos = service.valid_repositories(@user.id, @business, repo_ids)
      assert_equal [45, 48], T.must(valid_repos).sort
    end

    test "business valid repos returns only adminable repos" do
      # Repos 45 and 200 are defined in the fixtures, 100 is deliberately used because it does not exist
      repo_ids = [45, 100, 200]
      repo_that_non_creator_is_admin_for = [200]
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: repo_ids))
      valid_repos = service.valid_repositories(@non_creator.id, @business, repo_ids)
      assert_equal repo_that_non_creator_is_admin_for, T.must(valid_repos).sort
    end

    test "business valid repos only returns user-owned repos for EMUs and GHES" do
      @repo_without_org = create(:private_repository, owner: @user, name: "user-owned-repo", force_user_owned: true, id: 300)
      user_repo_expected = GitHub.enterprise? || TestEnv.test_with_all_emus?

      # Repos 45 and 48 are defined in the fixtures
      repo_ids = [45, 48, 300]
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: repo_ids))
      valid_repos = service.valid_repositories(@user.id, @business, repo_ids)

      if user_repo_expected
        assert_same_elements [45, 48, 300], T.must(valid_repos)
      else
        assert_same_elements [45, 48], T.must(valid_repos)
      end
    end

    test "if a selected repo is transferred to another org" do
      # Repos 45-48 are defined in the fixtures

      org_repo_ids = @org.repositories.ids

      # Transfer foo_repo from github to hubgit
      @foo_repo.update!(owner: @other_org)
      @org.reload

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: [45, 46, 47, 48]))
      valid_repos = service.valid_repositories(@user.id, @org, org_repo_ids)

      expected_repos = (org_repo_ids - [@foo_repo.id]).sort
      actual_repos = T.must(valid_repos).sort

      assert_equal expected_repos, actual_repos
    end

    test "allows user owned repositories if enterprise managed" do
      skip unless TestEnv.test_in_multitenancy_mode? || TestEnv.test_with_all_emus?

      mt_user = create(:emu, business: @business)
      mt_repo = create(:private_repository, force_user_owned: true, owner: mt_user)

      repo_ids = [mt_repo.id]
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: repo_ids))
      valid_repos = service.valid_repositories(@user.id, @business, repo_ids)
      assert_same_elements repo_ids, valid_repos
    end

    test "removes user owned repositories if the business hasn't purchased advanced security" do
      skip unless TestEnv.test_in_multitenancy_mode? || TestEnv.test_with_all_emus?
      @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)

      mt_user = create(:emu, business: @business)
      mt_repo = create(:private_repository, force_user_owned: true, owner: mt_user)

      repo_ids = [mt_repo.id]
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(res(repository_ids: repo_ids))
      valid_repos = service.valid_repositories(@user.id, @business, repo_ids)
      assert_equal [], T.must(valid_repos).sort
    end
  end

  context "#validate_secret_scanning_repositories" do
    test "service call" do
      enabled_repos = T.let(nil, T.nilable(T::Set[Integer]))
      VCR.use_cassette "secret-scanning/custom_patterns/validate_enabled_repos" do
        enabled_repos = service.validate_secret_scanning_repositories([1, 2, 3, 4])
      end

      assert_equal [1, 2, 3].to_set, enabled_repos
    end

    test "returns with over 1000 repos gets sliced" do
      first_response = ResponseMock.new(
        data: GitHub::Proto::SecretScanning::Api::V2::ValidateEnabledReposResponse.new
      )

      second_response = ResponseMock.new(
        data: GitHub::Proto::SecretScanning::Api::V2::ValidateEnabledReposResponse.new(repository_ids: [1001, 1002, 1003])
      )

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:validate_enabled_repos).returns(first_response).then.returns(second_response)
      enabled_repos = service.validate_secret_scanning_repositories((1..1500).to_a)

      assert_equal [1001, 1002, 1003].to_set, enabled_repos
    end

    test "returns with 2 batched calls" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [1] }).returns(res(repository_ids: [1]))
      GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [2] }).returns(res(repository_ids: [2]))
      SecretScanning::Services::CustomPatternsService.stub_const(:VALIDATE_ENABLED_REPOS_MAX, 1) do
        ids = service.validate_secret_scanning_repositories([1, 2])
        assert_equal Set.new([1, 2]), ids
      end
    end

    test "returns with filtered results" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [1, 2] }).returns(res(repository_ids: [1]))
      GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [3, 4] }).returns(res(repository_ids: [3]))
      SecretScanning::Services::CustomPatternsService.stub_const(:VALIDATE_ENABLED_REPOS_MAX, 2) do
        ids = service.validate_secret_scanning_repositories([1, 2, 3, 4])
        assert_equal Set.new([1, 3]), ids
      end
    end

    context "returns nil" do
      test "when response error" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [1] }).returns(res(repository_ids: [1]))
        GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [2] }).returns(res_error)
        SecretScanning::Services::CustomPatternsService.stub_const(:VALIDATE_ENABLED_REPOS_MAX, 1) do
          ids = service.validate_secret_scanning_repositories([1, 2])
          assert_nil ids
        end
      end

      test "when response nil" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [1] }).returns(res(repository_ids: [1]))
        GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [2] }).returns(nil)
        SecretScanning::Services::CustomPatternsService.stub_const(:VALIDATE_ENABLED_REPOS_MAX, 1) do
          ids = service.validate_secret_scanning_repositories([1, 2])
          assert_nil ids
        end
      end

      test "when response data nil" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [1] }).returns(res(repository_ids: [1]))
        GitHub::TokenScanning::Service::Client.any_instance.expects(:validate_enabled_repos).with({ repository_ids: [2] }).returns(nil_data)
        SecretScanning::Services::CustomPatternsService.stub_const(:VALIDATE_ENABLED_REPOS_MAX, 1) do
          ids = service.validate_secret_scanning_repositories([1, 2])
          assert_nil ids
        end
      end
    end
  end

  context "#cancel_dry_run_service" do
    test "succeeds" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:cancel_dry_runs_for_custom_pattern).returns(res)
      assert service.cancel_dry_run_service(id: 1, scan_ids: [1], owner: @org, owner_scope: :ORGANIZATION_SCOPE)
    end

    test "returns false if tss errors" do
      GitHub::TokenScanning::Service::Client.any_instance.expects(:cancel_dry_runs_for_custom_pattern).returns(nil)
      refute service.cancel_dry_run_service(id: 1, scan_ids: [1], owner: @org, owner_scope: :ORGANIZATION_SCOPE)
      GitHub::TokenScanning::Service::Client.any_instance.expects(:cancel_dry_runs_for_custom_pattern).returns(res_error)
      refute service.cancel_dry_run_service(id: 1, scan_ids: [1], owner: @org, owner_scope: :ORGANIZATION_SCOPE)
    end
  end

  test "#get_generated_expressions" do
    options = {
      description: "test",
      examples: "test",
      user_id: @user.id,
    }

    GitHub::TokenScanning::Service::Client.any_instance.expects(:get_generated_expressions).with(options).returns(:data)
    assert service.get_generated_expressions("test", "test")
  end

  context "#check_for_custom_patterns_twirp_error" do
    test "returns generic message when response is nil" do
      error, code = service.check_for_custom_patterns_twirp_error(nil)
      assert_equal SecretScanning::Services::CustomPatternsService::GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE, error
      assert_nil code
    end

    test "returns nil when error is nil" do
      error, code = service.check_for_custom_patterns_twirp_error(Twirp::ClientResp.new(data: nil, error: nil))
      assert_nil error
      assert_nil error
    end

    test "returns error message and code for twirp errors" do
      error, code = service.check_for_custom_patterns_twirp_error(Twirp::ClientResp.new(data: nil, error: Twirp::Error.invalid_argument("foo")))
      assert_equal "foo", error
      assert_equal :invalid_argument, code
    end
  end

  private

  sig { returns(SecretScanning::Services::CustomPatternsService) }
  def service
    SecretScanning::Services::CustomPatternsService.new(@user)
  end

  def res(**data)
    ResponseMock.new(
      data: ResponseDataMock.new(**data),
      error: nil,
    )
  end

  def nil_data
    ResponseMock.new(
      data: nil,
      error: nil,
    )
  end

  def res_error(data: "forcing data to exist just so it goes to error case", error: "im an error")
    ResponseMock.new(
      data: data,
      error: error,
    )
  end
end
