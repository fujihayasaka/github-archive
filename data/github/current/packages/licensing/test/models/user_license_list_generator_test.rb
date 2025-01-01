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
  end

  def user_list(**opts)
    VCR.use_cassette("get-active-committers", persist_with: :turboghas) do |cassette|
      T.cast(cassette.http_interactions, VCR::Cassette::HTTPInteractionList).interactions.each do |interaction|
        resp = ::Turboghas::Proto::GetActiveCommittersResponse.decode_json(interaction.response.body)
        resp.users = Google::Protobuf::RepeatedField.new(:message, ::Turboghas::Proto::GetActiveCommittersResponse::User, [::Turboghas::Proto::GetActiveCommittersResponse::User.new(id: @normal.id)])
        interaction.response.body = ::Turboghas::Proto::GetActiveCommittersResponse.encode_json(resp)
      end

      UserLicenseListGenerator.new(**opts).run
    end
  end

  def row_for(user, users = user_list)
    row = users.detect { |r| r[:user_id] == user.id }
    assert row, "expected to find a row for user #{user.login} (#{user.id})"
    row
  end

  def row_for_without_user_info(user)
    row_for(user, user_list(include_full_user_info: false))
  end

  if GitHub.enterprise?
    test "handles an error during advanced_security_user_ids" do
      response_1 = Twirp::ClientResp.new(data: nil, error: Twirp::Error.new(:internal, "something went wrong"))

      ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_active_committers).returns(response_1)

      assert user_list.all? { |row| row[:using_advanced_security].nil? }
    end

    test "does not include organizations" do
      refute_includes user_list.map { |row| row[:login] }, @org_a.login
      refute_includes user_list.map { |row| row[:login] }, @org_b.login
    end

    test "does not include suspended users" do
      refute_includes user_list.map { |row| row[:login] }, @suspended.login
    end

    test "does not include uncounted users" do
      uncounted_user = create :user, login: "uncounted-user"
      assert_includes user_list.map { |row| row[:login] }, uncounted_user.login

      User.stub(:logins_to_exclude_from_counts, User.logins_to_exclude_from_counts << uncounted_user.login) do
        refute_includes user_list.map { |row| row[:login] }, uncounted_user.login
      end
    end

    test "includes advanced security committers" do
      advanced_security_committers = user_list.select { |row| row[:using_advanced_security] }.map { |row| row[:login] }
      assert_includes advanced_security_committers, @normal.login
      assert_equal 1, advanced_security_committers.size
    end

    context "with include_full_user_info enabled" do
      test "includes user logins" do
        logins = [@normal, @cas, @github_admin, @admin].map(&:login)
        assert_same_elements logins, user_list.map { |row| row[:login] }
      end

      test "includes users profile name" do
        name = row_for(@normal)[:profile_name]
        assert_equal @normal.profile_name, name
      end

      test "includes users email addresses" do
        emails = row_for(@normal)[:emails]
        assert_equal @normal.email, emails.first[:email]
        assert emails.first[:primary]
        assert_equal "normaluseralias@example.com", emails.last[:email]
        refute emails.last[:primary]
      end

      test "includes user's admin role" do
        assert row_for(@admin)[:site_admin]
        refute row_for(@normal)[:site_admin]
      end

      test "includes user's creation date" do
        assert_equal @normal.created_at.to_formatted_s(:db), row_for(@normal)[:created_at]
      end
    end

    context "with include_full_user_info disabled" do
      test "does not include user logins" do
        user_list(include_full_user_info: false).each { |row| assert_nil row[:login] }
      end

      test "does not include users profile name" do
        assert_nil row_for_without_user_info(@normal)[:profile_name]
      end

      test "includes users email addresses" do
        emails = row_for_without_user_info(@normal)[:emails]
        assert_equal @normal.email, emails.first[:email]
        assert emails.first[:primary]
        assert_equal "normaluseralias@example.com", emails.last[:email]
        refute emails.last[:primary]
      end

      test "does not include user's admin role" do
        assert_nil row_for_without_user_info(@admin)[:site_admin]
        assert_nil row_for_without_user_info(@normal)[:site_admin]
      end

      test "does not include user's creation date" do
        assert_nil row_for_without_user_info(@normal)[:created_at]
      end
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
        assert_equal 2, rows.size
        assert_includes names, @normal.login
        assert_includes names, @cas.login
      end
    end

    context "with restrict_type of :suspended" do
      test "ignores :suspended and returns everyone" do
        logins = [@normal, @cas, @github_admin, @admin].map(&:login)
        rows = user_list(restrict_type: :suspended)
        assert_same_elements logins, rows.map { |row| row[:login] }
      end
    end

    context "with restrict_type of :builtin" do
      test "in default authentication, lists all users" do
        logins = [@normal, @cas, @github_admin, @admin].map(&:login)
        assert_same_elements logins, user_list(restrict_type: :builtin).map { |row| row[:login] }
      end

      test "in external authentication and no fallback, lists no users" do
        with_auth_mode(:cas) do
          assert_empty user_list(restrict_type: :builtin)
        end
      end

      test "in external authentication and fallback enabled, only lists built-in users" do
        with_auth_mode(:cas, fallback: true) do
          logins = [@normal, @github_admin, @admin].map(&:login)
          assert_same_elements logins, user_list(restrict_type: :builtin).map { |row| row[:login] }
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
