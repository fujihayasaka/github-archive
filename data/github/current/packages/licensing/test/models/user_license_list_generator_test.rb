# typed: true
# frozen_string_literal: true

require "test_helper"
require "turboghas"

class UserLicenseListGeneratorTest < GitHub::TestCase
  include AuthenticationHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    # can't have any other users getting in the way!
    # But keep the ghost around so we have an actor for callbacks
    User.where.not(id: User.ghost.id).delete_all

    @normal = create :user
    @normal.profile_name = "Normal User"
    @normal.add_email "normaluseralias@example.com"
    @normal.save
    @cas = create :user
    create(:cas_mapping, user: @cas)

    @admin = create :staff_admin_user
    # This is created by factory_bot when creating a staff user.
    @github_admin = Organization.find_by_login("github").admin

    @org_a = create :organization, admin: @admin
    @team_a = create :team, organization: @org_a
    @team_a.add_member @normal
    @org_b = create :organization, admin: @admin
    @team_b = create :team, organization: @org_b
    @team_b.add_member @normal

    @suspended = create :suspended_user

    @ghas_user = create :user
    @ghas_user.add_email "ghas-user@example.com"
    @ghas_user.save

    @code_scanning_user = create :user
    @code_scanning_user.add_email "code-scanning-user@example.com"
    @code_scanning_user.save

    @secret_protection_user = create :user
    @secret_protection_user.add_email "secret-protection-user@example.com"
    @secret_protection_user.save

    @code_scanning_secret_protection_user = create :user
    @code_scanning_secret_protection_user.add_email "code-scanning-secret-protection-user@example.com"
    @code_scanning_secret_protection_user.save
  end

  def program_turboghas
    ::Turboghas::AdvancedSecurityAPI.any_instance.expects(:get_active_committers)
      .with(
        entity_id: GitHub.global_business.id,
        entity_type: :ENTITY_TYPE_BUSINESS,
        features: GitHub::Turboghas::SKU::Bundled.features,
      )
      .returns(Twirp::ClientResp.new(data: ::Turboghas::Proto::GetActiveCommittersResponse.new(
        users: [{ id: @ghas_user.id }],
      )))
      .at_least(0)
    ::Turboghas::AdvancedSecurityAPI.any_instance.expects(:get_active_committers)
      .with(
        entity_id: GitHub.global_business.id,
        entity_type: :ENTITY_TYPE_BUSINESS,
        features: GitHub::Turboghas::SKU::CodeSecurity.features,
      )
      .returns(Twirp::ClientResp.new(data: ::Turboghas::Proto::GetActiveCommittersResponse.new(
        users: [{ id: @code_scanning_user.id }, { id: @code_scanning_secret_protection_user.id }],
      )))
      .at_least(0)
    ::Turboghas::AdvancedSecurityAPI.any_instance.expects(:get_active_committers)
      .with(
        entity_id: GitHub.global_business.id,
        entity_type: :ENTITY_TYPE_BUSINESS,
        features: GitHub::Turboghas::SKU::SecretSecurity.features,
      )
      .returns(Twirp::ClientResp.new(data: ::Turboghas::Proto::GetActiveCommittersResponse.new(
        users: [{ id: @secret_protection_user.id }, { id: @code_scanning_secret_protection_user.id }],
      )))
      .at_least(0)
  end

  sig { params(user: User, users: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Hash[Symbol, T.untyped]) }
  def row_for(user, users)
    row = users.detect { |r| r[:user_id] == user.id }
    assert row, "expected to find a row for user #{user.login} (#{user.id})"
    T.must(row)
  end

  if GitHub.enterprise?
    test "handles an error during advanced_security_user_ids" do
      response_1 = Twirp::ClientResp.new(data: nil, error: Twirp::Error.new(:internal, "something went wrong"))

      ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_active_committers).returns(response_1)
      users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run

      assert users.all? { |row| row[:using_advanced_security].nil? }
    end

    test "does not include organizations" do
      program_turboghas
      users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
      refute_includes users.map { |row| row[:login] }, @org_a.login
      refute_includes users.map { |row| row[:login] }, @org_b.login
    end

    test "does not include suspended users" do
      program_turboghas
      users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
      refute_includes users.map { |row| row[:login] }, @suspended.login
    end

    test "does not include uncounted users" do
      program_turboghas

      uncounted_user = create :user, login: "uncounted-user"
      users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
      assert_includes users.map { |row| row[:login] }, uncounted_user.login

      User.stub(:logins_to_exclude_from_counts, User.logins_to_exclude_from_counts << uncounted_user.login) do
        users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
        refute_includes users.map { |row| row[:login] }, uncounted_user.login
      end
    end

    test "includes advanced security committers" do
      program_turboghas

      users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run

      advanced_security_committers = users.select { |row| row[:using_advanced_security] }.map { |row| row[:login] }
      assert_includes advanced_security_committers, @ghas_user.login
      assert_equal 1, advanced_security_committers.size

      code_security_committers = users.select { |row| row[:using_code_security] }.map { |row| row[:login] }
      assert_includes code_security_committers, @code_scanning_user.login
      assert_includes code_security_committers, @code_scanning_secret_protection_user.login
      assert_equal 2, code_security_committers.size

      secret_protection_committers = users.select { |row| row[:using_secret_protection] }.map { |row| row[:login] }
      assert_includes secret_protection_committers, @secret_protection_user.login
      assert_includes secret_protection_committers, @code_scanning_secret_protection_user.login
      assert_equal 2, secret_protection_committers.size
    end

    context "with include_full_user_info enabled" do
      test "includes user logins" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
        logins = [@normal, @cas, @github_admin, @admin, @ghas_user, @code_scanning_user, @secret_protection_user, @code_scanning_secret_protection_user].map(&:login)
        assert_same_elements logins, users.map { |row| row[:login] }
      end

      test "includes users profile name" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
        name = row_for(@normal, users)[:profile_name]
        assert_equal @normal.profile_name, name
      end

      test "includes users email addresses" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
        emails = row_for(@normal, users)[:emails]
        assert_equal @normal.email, emails.first[:email]
        assert emails.first[:primary]
        assert_equal "normaluseralias@example.com", emails.last[:email]
        refute emails.last[:primary]
      end

      test "includes user's admin role" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
        assert row_for(@admin, users)[:site_admin]
        refute row_for(@normal, users)[:site_admin]
      end

      test "includes user's creation date" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: nil).run
        assert_equal @normal.created_at.to_formatted_s(:db), row_for(@normal, users)[:created_at]
      end
    end

    context "with include_full_user_info disabled" do
      test "does not include user logins" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: false, restrict_type: nil).run
        users.each { |row| assert_nil row[:login] }
      end

      test "does not include users profile name" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: false, restrict_type: nil).run
        assert_nil row_for(@normal, users)[:profile_name]
      end

      test "includes users email addresses" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: false, restrict_type: nil).run
        emails = row_for(@normal, users)[:emails]
        assert_equal @normal.email, emails.first[:email]
        assert emails.first[:primary]
        assert_equal "normaluseralias@example.com", emails.last[:email]
        refute emails.last[:primary]
      end

      test "does not include user's admin role" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: false, restrict_type: nil).run
        T.must(@admin)
        T.must(@normal)
        assert_nil row_for(@admin, users)[:site_admin]
        assert_nil row_for(@normal, users)[:site_admin]
      end

      test "does not include user's creation date" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: false, restrict_type: nil).run
        assert_nil row_for(@normal, users)[:created_at]
      end
    end

    context "with restrict_type of :admins" do
      test "only lists admins" do
        program_turboghas

        rows = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: :admins).run
        assert_equal 1, rows.size
        assert_equal @admin.login, T.must(rows[0])[:login]
      end
    end

    context "with restrict_type of :users" do
      test "only lists regular users" do
        program_turboghas

        rows = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: :users).run
        names = rows.map { |r| r[:login] }
        assert_equal 6, rows.size
        assert_includes names, @normal.login
        assert_includes names, @cas.login
      end
    end

    context "with restrict_type of :suspended" do
      test "ignores :suspended and returns everyone" do
        program_turboghas

        logins = [@normal, @cas, @github_admin, @admin, @ghas_user, @code_scanning_user, @secret_protection_user, @code_scanning_secret_protection_user].map(&:login)
        rows = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: :suspended).run
        assert_same_elements logins, rows.map { |row| row[:login] }
      end
    end

    context "with restrict_type of :builtin" do
      test "in default authentication, lists all users" do
        program_turboghas

        users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: :builtin).run
        logins = [@normal, @cas, @github_admin, @admin, @ghas_user, @code_scanning_user, @secret_protection_user, @code_scanning_secret_protection_user].map(&:login)
        assert_same_elements logins, users.map { |row| row[:login] }
      end

      test "in external authentication and no fallback, lists no users" do
        with_auth_mode(:cas) do
          program_turboghas

          users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: :builtin).run
          assert_empty users
        end
      end

      test "in external authentication and fallback enabled, only lists built-in users" do
        with_auth_mode(:cas, fallback: true) do
          program_turboghas

          users = UserLicenseListGenerator.new(include_full_user_info: true, restrict_type: :builtin).run
          logins = [@normal, @github_admin, @admin, @ghas_user, @code_scanning_user, @secret_protection_user, @code_scanning_secret_protection_user].map(&:login)
          assert_same_elements logins, users.map { |row| row[:login] }
        end
      end
    end

  else # dotcom mode

    test "does not run in dotcom mode" do
      assert_raises UserListGenerator::Error, /enterprise/ do
        UserLicenseListGenerator.new.run
      end
    end
  end

end
