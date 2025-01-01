# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/enterprise_accounts/kv"

class UserCsvGeneratorTest < GitHub::TestCase
  include AuthenticationHelpers

  fixtures do
    # can't have any other users getting in the way!
    # But keep the ghost around so we have an actor for callbacks
    User.where.not(id: User.ghost.id).delete_all

    @normal = create :user, login: "normal-user"
    @large_scale_contributor = create :user, login: "large-scale-contributor-user"
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

  def csv(show_header: false, restrict_type: nil)
    output = StringIO.new
    UserCSVGenerator.new(output_io: output, show_header: show_header, restrict_type: restrict_type).run
    output.rewind
    T.must(output.read).split("\n").map { |line| line.split(",") }
  end

  def row_for(user)
    row = csv.detect { |r| r[0] == user.login }
    assert row, "expected to find a row for user #{user.login}"
    row
  end

  if GitHub.enterprise?

    test "includes user logins" do
      logins = [@normal, @cas, @github_admin, @admin, @suspended, @large_scale_contributor].map(&:login).sort
      assert_equal logins, csv.map { |row| row[0] }
    end

    test "does not include organizations" do
      refute_includes csv.map { |row| row[0] }, @org_a.login
      refute_includes csv.map { |row| row[0] }, @org_b.login
    end

    test "includes users primary emails" do
      email = row_for(@normal)[1]
      assert_equal @normal.primary_user_email.email, email
    end

    test "includes user's role for admin and non admins" do
      assert_equal "user", row_for(@normal)[2]
      assert_equal "admin", row_for(@admin)[2]
    end

    test "includes a users' ssh key count" do
      assert_equal "0", row_for(@normal)[3]
      create(:public_key, user: @normal)
      assert_equal "1", row_for(@normal)[3]
    end

    test "includes a users' org membership count based on team membership" do
      assert_equal "2", row_for(@normal)[4]
      @team_b.remove_member @normal
      assert_equal "1", row_for(@normal)[4]
    end

    test "includes a users' repository count" do
      assert_equal "0", row_for(@normal)[5]
      create(:repository, :minimal, owner: @normal)
      assert_equal "1", row_for(@normal)[5]
    end

    test "includes suspended status" do
      assert_equal "active", row_for(@normal)[6]
      assert_equal "suspended", row_for(@suspended)[6]
    end

    test "includes large contributor status" do
      EnterpriseAccounts::KV.store.set("user.large_scale_contributor.#{@large_scale_contributor.id}", "true")
      assert_equal "false", row_for(@normal)[7]
      assert_equal "true", row_for(@large_scale_contributor)[7]
    end

    test "includes last logged ip address when present" do
      assert_equal "N/A", row_for(@normal)[8]
      @normal.update_attribute :last_ip, "127.0.0.1"
      assert_equal "127.0.0.1", row_for(@normal)[8]
    end

    test "includes user's creation date" do
      assert_equal @normal.created_at.to_formatted_s(:db), row_for(@normal)[9]
    end

    context "when show_header is true" do
      test "lists the header as the first row" do
        assert_equal UserCSVGenerator::HEADER.split(","), csv(show_header: true)[0]
      end
    end

    context "with restrict_type of :admins" do
      test "only lists admins" do
        rows = csv(restrict_type: :admins)
        assert_equal 1, rows.size
        assert_equal @admin.login, rows[0][0]
      end
    end

    context "with restrict_type of :users" do
      test "only lists regular users" do
        rows = csv(restrict_type: :users)
        names = rows.map { |r| r[0] }
        assert_equal 4, rows.size
        assert_includes names, @normal.login
        assert_includes names, @cas.login
        assert_includes names, @suspended.login
        assert_includes names, @large_scale_contributor.login
      end
    end

    context "with restrict_type of :suspended" do
      test "only lists suspended users" do
        rows = csv(restrict_type: :suspended)
        assert_equal 1, rows.size
        assert_equal @suspended.login, rows[0][0]
      end

      test "includes suspended admins" do
        @admin.suspend("because!")
        rows = csv(restrict_type: :suspended)
        assert_equal 2, rows.size
        assert_equal @admin.login, rows[0][0]
      end
    end

    context "with restrict_type of :builtin" do
      test "in default authentication, lists all users" do
        logins = [@normal, @cas, @github_admin, @admin, @suspended, @large_scale_contributor].map(&:login).sort
        assert_equal logins, csv(restrict_type: :builtin).map { |row| row[0] }
      end

      test "in external authentication and no fallback, lists no users" do
        with_auth_mode(:cas) do
          assert_empty csv(restrict_type: :builtin)
        end
      end

      test "in external authentication and fallback enabled, only lists built-in users" do
        with_auth_mode(:cas, fallback: true) do
          logins = [@normal, @github_admin, @admin, @suspended, @large_scale_contributor].map(&:login).sort
          assert_equal logins, csv(restrict_type: :builtin).map { |row| row[0] }
        end
      end
    end

  else # dotcom mode

    test "does not run in dotcom mode" do
      assert_raises UserListGenerator::Error, /enterprise/ do
        UserCSVGenerator.new(output_io: StringIO.new).run
      end
    end
  end

end
