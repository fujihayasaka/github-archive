# typed: true
# frozen_string_literal: true
require "test_helper"

module RepoFeatureAvailabilityTest
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  protected

  sig do
    params(
      check_fn: T::proc.params(arg0: Repository).returns(T::Boolean),
      test_fixtures: T::Hash[Symbol, Repository],
      matrix: T::Hash[Symbol, T::Boolean],
    ).void
  end
  def assert_availability_on_all_repos(check_fn:, test_fixtures:, matrix:)
    # Ensure that the matrix covers all repositories created in the test fixtures
    assert_equal test_fixtures.keys.sort, matrix.keys.sort, "Matrix does not cover all eligible repos"

    assert_on_matrix(check_fn:, test_fixtures:, matrix:)
  end

  sig do
    params(
      check_fn: T::proc.params(arg0: Repository).returns(T::Boolean),
      test_fixtures: T::Hash[Symbol, Repository],
      matrix: T::Hash[Symbol, T::Boolean],
    ).void
  end
  def assert_on_matrix(check_fn:, test_fixtures:, matrix:)
    failed = T.let(false, T::Boolean)
    errors = T.let([], T::Array[String])
    matrix.each do |id, expected|
      repo = T.must(test_fixtures[id])

      actual = check_fn.call(repo)
      if expected != actual
        errors << "Expected availability for #{id} to be #{expected}, but was #{actual}"
        failed = true
      end
    end
    refute failed, errors.join("\n")
  end

  sig { params(opts: T::Hash[Symbol, T::Boolean]).returns(T::Hash[Symbol, Repository]) }
  def create_fixtures(opts:)
    if GitHub.enterprise?
      create_fixtures_ghes(opts:)
    else
      create_fixtures_ghec(opts:)
    end
  end

  sig { params(opts: T::Hash[Symbol, T::Boolean]).returns(T::Hash[Symbol, Repository]) }
  def create_fixtures_ghec(opts:)
    repos = {}
    create(:business, :enterprise_managed).tap do |mt_biz|
      non_mt_owner = mt_biz.owners.first
      mt_owner = mt_biz.find_first_emu_owner

      if opts[:mark_ghas_as_purchased]
        mt_biz.mark_advanced_security_as_purchased_for_entity(actor: mt_owner)
      end

      mt_owner.tap do |u|
        # EMU accounts cannot create public/internal repos
        repos[:emu_private_repo] = create(:private_repository, owner: u, force_user_owned: true)
        repos[:emu_archived_repo] = create(:archived_repository, owner: u, public: false)
      end

      create(:organization, business: mt_biz, admin: mt_owner).tap do |u|
        repos[:org_public_repo] = create(:public_repository, owner: u)
        repos[:org_private_repo] = create(:private_repository, owner: u)
        repos[:org_internal_repo] = create(:internal_repository, owner: u)

        repos[:org_archived_public_repo] = create(:archived_repository, public: true, owner: u)
        repos[:org_archived_private_repo] = create(:archived_repository, public: false, owner: u)
        repos[:org_archived_internal_repo] = create(:private_repository, internal: true, maintained: false, archived_at: 30.minutes.ago, owner: u)
      end
    end

    create(:user).tap do |u|
      repos[:user_public_repo] = create(:public_repository, owner: u)
      repos[:user_private_repo] = create(:private_repository, owner: u)

      repos[:user_archived_public_repo] = create(:archived_repository, public: true, owner: u)
      repos[:user_archived_private_repo] = create(:archived_repository, public: false, owner: u)
    end

    if opts[:enable_ghas]
      # do not care whether any errors come from this, just try to enable it on everything
      repos.values.each do |repo|
        repo.enable_advanced_security(actor: repo.owner)
      end
    end

    if opts[:enable_token_scanning]
      # do not care whether any errors come from this, just try to enable it on everything
      repos.values.each do |repo|
        SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
      end
    end

    repos
  end

  sig { params(opts: T::Hash[Symbol, T::Boolean]).returns(T::Hash[Symbol, Repository]) }
  def create_fixtures_ghes(opts:)
    repos = {}

    GitHub::Enterprise.ensure_business!
    GitHub.global_business.tap do |biz|
      owner = biz.owners.first

      create(:organization, business: biz, admin: owner).tap do |u|
        repos[:org_public_repo] = create(:public_repository, owner: u)
        repos[:org_private_repo] = create(:private_repository, owner: u)
        repos[:org_internal_repo] = create(:internal_repository, owner: u)

        repos[:org_archived_public_repo] = create(:archived_repository, public: true, owner: u)
        repos[:org_archived_private_repo] = create(:archived_repository, public: false, owner: u)
        repos[:org_archived_internal_repo] = create(:private_repository, internal: true, maintained: false, archived_at: 30.minutes.ago, owner: u)
      end
    end

    create(:user).tap do |u|
      repos[:user_public_repo] = create(:public_repository, owner: u)
      repos[:user_private_repo] = create(:private_repository, owner: u)

      repos[:user_archived_public_repo] = create(:archived_repository, public: true, owner: u)
      repos[:user_archived_private_repo] = create(:archived_repository, public: false, owner: u)
    end

    if opts[:enable_ghas]
      # do not care whether any errors come from this, just try to enable it on everything
      repos.values.each do |repo|
        repo.enable_advanced_security(actor: repo.owner)
      end
    end

    if opts[:enable_token_scanning]
      # do not care whether any errors come from this, just try to enable it on everything
      repos.values.each do |repo|
        SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: repo.owner)
      end
    end

    repos
  end
end
