# typed: true
# frozen_string_literal: true

require "test_helper"

class UserListGeneratorTest < GitHub::TestCase
  include AuthenticationHelpers

  fixtures do
    # can't have any other users getting in the way!
    # But keep the ghost around so we have an actor for callbacks
    User.where.not(id: User.ghost.id).delete_all

    @normal = create :user, login: "normal-user"
    @cas = create :user, login: "cas-user", cas_mapping: CasMapping.create(username: "cas_user")

    @admin = create :staff_admin_user, login: "admin-user"
    # This is created by factory_bot when creating a staff user.
    @github_admin = Organization.find_by_login("github").admin

    @org_a = create :organization, login: "org-a", admin: @admin
    @team_a = create :team, organization: @org_a
    @team_a.add_member @normal
    @org_b = create :organization, login: "org-b", admin: @admin
    @team_b = create :team, organization: @org_b
    @team_b.add_member @normal

    @suspended = create :suspended_user
  end

  def user_list(**opts)
    UserListGenerator.new(**opts).run
  end

  def row_for(user)
    row = user_list.detect { |r| r[:login] == user.login }
    assert row, "expected to find a row for user #{user.login}"
    row
  end

  if GitHub.enterprise?

    test "includes user logins" do
      logins = [@normal, @cas, @github_admin, @admin, @suspended].map(&:login).sort
      assert_equal logins, user_list.map { |row| row[:login] }
    end

    test "does not include organizations" do
      refute_includes user_list.map { |row| row[:login] }, @org_a.login
      refute_includes user_list.map { |row| row[:login] }, @org_b.login
    end

    test "includes users primary emails" do
      email = row_for(@normal)[:email]
      assert_equal @normal.primary_user_email.email, email
    end

    test "includes user's creation date" do
      assert_equal @normal.created_at.to_formatted_s(:db), row_for(@normal)[:creation_date]
    end

    context "with restrict_type of :admins" do
      test "only lists admins" do
        rows = user_list(restrict_type: :admins)
        assert_equal 1, rows.size
        assert_equal @admin.login, rows[0][:login]
      end
    end

    context "with restrict_type of :users" do
      test "only lists regular users" do
        rows = user_list(restrict_type: :users)
        names = rows.map { |r| r[:login] }
        assert_equal 3, rows.size
        assert_includes names, @normal.login
        assert_includes names, @cas.login
        assert_includes names, @suspended.login
      end
    end

    context "with restrict_type of :suspended" do
      test "only lists suspended users" do
        rows = user_list(restrict_type: :suspended)
        assert_equal 1, rows.size
        assert_equal @suspended.login, rows[0][:login]
      end

      test "includes suspended admins" do
        @admin.suspend("because!")
        rows = user_list(restrict_type: :suspended)
        assert_equal 2, rows.size
        assert_equal @admin.login, rows[0][:login]
      end
    end

    context "with restrict_type of :builtin" do
      test "in default authentication, lists all users" do
        logins = [@normal, @cas, @github_admin, @admin, @suspended].map(&:login).sort
        assert_equal logins, user_list(restrict_type: :builtin).map { |row| row[:login] }
      end

      test "in external authentication and no fallback, lists no users" do
        with_auth_mode(:cas) do
          assert_empty user_list(restrict_type: :builtin)
        end
      end

      test "in external authentication and fallback enabled, only lists built-in users" do
        with_auth_mode(:cas, fallback: true) do
          logins = [@normal, @github_admin, @admin, @suspended].map(&:login).sort
          assert_equal logins, user_list(restrict_type: :builtin).map { |row| row[:login] }
        end
      end
    end

  else # dotcom mode

    test "does not run in dotcom mode" do
      assert_raises UserListGenerator::Error, /enterprise/ do
        UserListGenerator.new.run
      end
    end
  end

end
