# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatManagement::CsvTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @organization = create(:copilot_for_business_enabled_organization, admin: @org_admin)
  end

  context "#parse" do
    test "parse csv with no errors" do
      create(:user, email: "octocat@github.com")
      create(:user, login: "ghosty")
      csv_file = ActionDispatch::Http::UploadedFile.new({
        filename: "users.csv",
        tempfile: File.open(file_fixture("copilot/valid_users.csv"), "rb"),
        type:  "text/csv"
      })

      result = Copilot::SeatManagement::Csv.parse(@organization, csv_file)
      results = T.must(result.value!)
      assert T.must(results[:github_users]).count == 2
      assert T.must(results[:email_users]).count == 2
      assert T.must(results[:found_errors]).count == 0
    end

    test "parse csv dedupes users" do
      create(:user, email: "octobuddy@github.com")
      create(:user, email: "catfan1234@github.com")
      create(:user, login: "christina", email: "90sfan@email.biz")
      create(:user, login: "casper")

      csv_file = ActionDispatch::Http::UploadedFile.new({
        filename: "users.csv",
        tempfile: File.open(file_fixture("copilot/duped_users.csv"), "rb"),
        type:  "text/csv"
      })

      result = Copilot::SeatManagement::Csv.parse(@organization, csv_file)
      results = T.must(result.value!)

      assert T.must(results[:github_users]).count == 4
      assert T.must(results[:email_users]).count == 1
      assert T.must(results[:found_errors]).count == 0
    end

    test "parse csv is case insensitive" do
      create(:user, login: "AVOCADO")
      create(:user, login: "BaNaNa")
      create(:user, login: "cocoNUT")
      create(:user, email: "dragonFRUIT@github.com")

      csv_file = ActionDispatch::Http::UploadedFile.new({
        filename: "users.csv",
        tempfile: File.open(file_fixture("copilot/mixed_case_users.csv"), "rb"),
        type:  "text/csv"
      })

      result = Copilot::SeatManagement::Csv.parse(@organization, csv_file)
      results = T.must(result.value!)

      assert T.must(results[:github_users]).count == 4
      assert T.must(results[:email_users]).count == 1
      assert T.must(results[:found_errors]).count == 0
    end

    test "parse csv with errors" do
      create(:user, email: "octocat@github.com")
      csv_file = ActionDispatch::Http::UploadedFile.new({
        filename: "valid_and_invalid_users.csv",
        tempfile: File.open(file_fixture("copilot/valid_and_invalid_users.csv"), "rb"),
        type:  "text/csv"
      })

      result = Copilot::SeatManagement::Csv.parse(@organization, csv_file)
      results = T.must(result.value!)
      assert T.must(results[:github_users]).count == 1
      assert T.must(results[:email_users]).count == 2
      assert T.must(results[:found_errors]).count == 3
    end

    test "test parsing for emu users" do
      enterprise = create(:business, :enterprise_managed_business, shortcode: "emu")

      emu = create(:emu, business: enterprise)

      owner = enterprise.owners.first
      org = create(:organization, business: enterprise, admin: owner)

      assert_equal enterprise, emu.enterprise_managed_business
      assert_equal org, enterprise.organizations.first

      org.add_member(emu)

      # to be kept in sync with copilot/emu_users.csv
      org.add_member(create(:emu, business: enterprise, login: "bk86517"))
      org.add_member(create(:emu, business: enterprise, login: "SM83814"))

      # adds an emu user, with thier org name suffixed
      org.add_member(create(:emu, business: enterprise, login: "gm08704", email: "gm08704+emu@mona.org"))

      csv_file = ActionDispatch::Http::UploadedFile.new({
        filename: "users.csv",
        tempfile: File.open(file_fixture("copilot/emu_users.csv"), "rb"),
        type:  "text/csv"
      })

      result = Copilot::SeatManagement::Csv.parse(org, csv_file)
      results = T.must(result.value!)

      assert_equal 0, T.must(results[:new_users]) # nobody is being invited
      assert_equal 3, T.must(results[:github_users]).count # there are 11 users on github
      assert_equal 0, T.must(results[:email_users]).count # nobody is being invited by email
      assert_equal 1, T.must(results[:found_errors]).count # one user doesnt existon github (match by :login)
      assert_equal 3, T.must(results[:total_users]) # so a totoal of 11 users will be added

      data = results[:github_users].map { |obj| Copilot::SeatManagement::Csv.serialize_user(obj) }

      # The email should not include the shortcode
      assert_equal "gm08704@mona.org", data.find { |obj| obj[:display_login] == "gm08704_emu" }[:email]

    end unless GitHub.enterprise?
  end

  context "parse_as_json" do
    test "returns a payload suitable for serialization" do
      create(:user, email: "octocat@github.com")
      create(:user, login: "ghosty")
      csv_file = ActionDispatch::Http::UploadedFile.new({
        filename: "users.csv",
        tempfile: File.open(file_fixture("copilot/valid_users.csv"), "rb"),
        type:  "text/csv"
      })

      result = Copilot::SeatManagement::Csv.parse_as_json(@organization, csv_file)

      assert T.must(result[:github_users]).count == 2
      assert T.must(result[:email_users]).count == 2
      assert T.must(result[:found_errors]).count == 0
      assert T.must(result[:new_users]) == 4
    end

    test "returns a consistent object if the csv fails to parse" do
      GitHub::Result.any_instance.stubs(:ok?).returns(false)
      csv_file = ActionDispatch::Http::UploadedFile.new({
        filename: "valid_users.csv",
        tempfile: File.open(file_fixture("copilot/valid_users.csv"), "rb"),
        type:  "text/csv"
      })

      result = Copilot::SeatManagement::Csv.parse_as_json(@organization, csv_file)

      assert T.must(result[:github_users]).empty?
      assert T.must(result[:email_users]).empty?
      assert T.must(result[:found_errors]).empty?
      assert T.must(result[:new_users]) == 0
    end

    test "properly serializes user objects" do
      create(:user, login: "ghosty")
      csv_file = ActionDispatch::Http::UploadedFile.new({
        filename: "users.csv",
        tempfile: File.open(file_fixture("copilot/valid_users.csv"), "rb"),
        type:  "text/csv"
      })

      result = Copilot::SeatManagement::Csv.parse_as_json(@organization, csv_file)

      user = result[:github_users][0]
      assert user.kind_of?(Hash)
      assert(user.keys.sort == [:id, :email, :display_login, :profile_name, :avatar, :is_new_user].sort)
    end


  end

  context "#save" do
    test "save csv results" do
      @organization.update(plan: "business", seats: 15)
      copilot_organization = Copilot::Organization.new(@organization)
      github_users = [create(:user), create(:user), create(:user), @org_admin]
      email_users = ["madeleine@loves.sharks", "david@loves.sharks"]
      Copilot::SeatManagement::Csv.save(
        copilot_organization,
        github_users.map(&:login),
        email_users,
        @org_admin,
      )
      assert Copilot::SeatAssignment.for_organization(@organization).count == 6
    end
  end
end if GitHub.copilot_enabled?
