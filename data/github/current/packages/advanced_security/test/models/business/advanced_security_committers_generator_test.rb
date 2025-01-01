# typed: true
# frozen_string_literal: true

require "test_helper"
require "hashdiff"

class AdvancedSecurityCommittersGeneratorTest < GitHub::TestCase
  include TurboghasHelpers

  fixtures do
    @org_1_user = create(:user)
    @org_2_user = create(:user)
    @org_1_user_2 = create(:user)
    @both_orgs_user = create(:user)
    @user_with_no_contributions = create(:user)

    @org_1 = create(:organization, admin: @org_1_user)
    @org_2 = create(:organization, admin: @org_2_user)
    @org_3 = create(:organization, admin: @user_with_no_contributions)

    @org_1.invite(@org_1_user_2, inviter: @org_1_user)
    @org_1.invite(@user_with_no_contributions, inviter: @org_1_user)
    @org_2.invite(@org_1_user, inviter: @org_2_user)
    @org_1.invite(@both_orgs_user, inviter: @org_1_user)
    @org_2.invite(@both_orgs_user, inviter: @org_2_user)

    @business = GitHub.global_business ? GitHub.global_business : create(:business, organizations: [@org_1, @org_2, @org_3])
    @business.mark_advanced_security_as_purchased_for_entity(actor: @org_1_user)
    [@org_1, @org_2, @org_3].each(&:reload)

    @org_1_repo = create(:private_repository, owner: @org_1)
    @org_2_repo = create(:private_repository, owner: @org_2)
    @org_1_repo_2 = create(:private_repository, owner: @org_1)
    @org_1_no_advanced_security_repo = create(:private_repository, owner: @org_1)
    @org_3_no_contributions_repo = create(:private_repository, owner: @org_3)

    @org_1_repo.enable_advanced_security!(actor: @org_1_user)
    @org_2_repo.enable_advanced_security!(actor: @org_2_user)
    @org_1_repo_2.enable_advanced_security!(actor: @org_1_user)
    @org_3_no_contributions_repo.enable_advanced_security!(actor: @user_with_no_contributions)
    @org_1_no_advanced_security_repo.disable_advanced_security!(actor: @org_1_user)
  end

  setup do
    stub_turboghas_summary(maximum_committers: 4, active_committers: 4)
    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(100)
    else
      @business.set_advanced_security_seats_for_entity(actor: @org_1_user, seats: 100)
    end
  end

  test "returns correct json for business's active committers" do
    # TurboGHAS returns the data ordered by repository NWO by default
    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetCommittersResponse.new(committers: [
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 1, login: "user-1", email: "user-1@localhost", repository_id: @org_1_repo.id, repository_nwo: @org_1_repo.name_with_owner, pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 2, login: "user-2", email: "user-2@localhost", repository_id: @org_1_repo_2.id, repository_nwo: @org_1_repo_2.name_with_owner, pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 3, login: "user-3", email: "user-3@localhost", repository_id: @org_1_repo_2.id, repository_nwo: @org_1_repo_2.name_with_owner, pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 4, login: "user-4", email: "user-4@localhost", repository_id: @org_2_repo.id, repository_nwo:  @org_2_repo.name_with_owner, pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
    ].sort_by(&:repository_nwo)))

    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_committers_for_business).returns(response)
    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_committers_for_owner).returns(response)

    # check this doesnt raise
    refute_empty Business::AdvancedSecurityCommittersGenerator.generate_json(@org_1)
    # check paging too far doesn't raise
    assert_empty Business::AdvancedSecurityCommittersGenerator.generate_json(@org_1, page: 100)[:repositories]

    data = Business::AdvancedSecurityCommittersGenerator.generate_json(@business)

    expected = { repositories: [
      {
        name: @org_1_repo.name_with_display_owner, advanced_security_committers: 1, advanced_security_committers_breakdown:  [
          { user_login: "user-1", last_pushed_date: "2023-06-13", last_pushed_email: "user-1@localhost" },
        ]
      },
      {
        name: @org_2_repo.name_with_display_owner, advanced_security_committers: 1, advanced_security_committers_breakdown:  [
          { user_login: "user-4", last_pushed_date: "2023-06-13", last_pushed_email: "user-4@localhost" },
        ]
      },
      {
        name: @org_1_repo_2.name_with_display_owner, advanced_security_committers: 2, advanced_security_committers_breakdown:  [
          { user_login: "user-2", last_pushed_date: "2023-06-13", last_pushed_email: "user-2@localhost" },
          { user_login: "user-3", last_pushed_date: "2023-06-13", last_pushed_email: "user-3@localhost" },
        ]
      }
    ].sort_by { |row| row[:name] }, total_count: 3, total_advanced_security_committers: 4, maximum_advanced_security_committers: 4, purchased_advanced_security_committers: 100 }

    assert_equal expected, data, Hashdiff.diff(data, expected)

    # check that multiple pages of repositories work
    (1..3).each do |page|
      data_page = Business::AdvancedSecurityCommittersGenerator.generate_json(@business, page: page, per_page: 1)
      expected_page = { repositories: [expected[:repositories][page - 1]], total_count: 3, total_advanced_security_committers: 4, maximum_advanced_security_committers: 4, purchased_advanced_security_committers: 100 }
      assert_equal expected_page, data_page, "Page #{page} FAILED:\n" + Hashdiff.diff(data_page, expected_page).to_s
    end
  end

  test "return the active committers for an enterprise" do
    org = create(:organization)
    repo_id = 2

    business = GitHub.global_business ? GitHub.global_business : create(:business, organizations: [org])

    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetCommittersResponse.new(committers: [
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 1, login: "user-1", email: "user-1@localhost", repository_id: 1, repository_nwo: "org-1/test-1", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 2, login: "user-2", email: "user-2@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 3, login: "user-3", email: "user-3@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 4, login: "user-4", email: "user-4@localhost", repository_id: 3, repository_nwo: "org-2/test-1", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
    ]))

    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_committers_for_business).returns(response)

    title_row, *rows = CSV.parse(Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: business))

    assert_equal ["User login", "Organization / repository", "Last pushed date", "Last pushed email"], title_row
    assert_same_elements [
      ["user-1", "org-1/test-1", "2023-06-13", "user-1@localhost"],
      ["user-2", "org-1/test-2", "2023-06-13", "user-2@localhost"],
      ["user-3", "org-1/test-2", "2023-06-13", "user-3@localhost"],
      ["user-4", "org-2/test-1", "2023-06-13", "user-4@localhost"],
    ], rows
  end

  test "return the additional committers for an enterprise" do
    org = create(:organization)
    repo_id = 2

    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetCommittersResponse.new(committers: [
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 1, login: "user-1", email: "user-1@localhost", repository_id: 1, repository_nwo: "org-1/test-1", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 2, login: "user-2", email: "user-2@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 3, login: "user-3", email: "user-3@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 4, login: "user-4", email: "user-4@localhost", repository_id: 3, repository_nwo: "org-2/test-1", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
    ]))

    business = GitHub.global_business ? GitHub.global_business : create(:business, organizations: [org])
    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_committers_for_business).returns(response)

    title_row, *rows = CSV.parse(Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: business, committer_type: :ADDITIONAL_COMMITTERS))

    assert_equal ["User login", "Organization / repository", "Last pushed date", "Last pushed email"], title_row
    assert_same_elements [
      ["user-1", "org-1/test-1", "2023-06-13", "user-1@localhost"],
      ["user-2", "org-1/test-2", "2023-06-13", "user-2@localhost"],
      ["user-3", "org-1/test-2", "2023-06-13", "user-3@localhost"],
      ["user-4", "org-2/test-1", "2023-06-13", "user-4@localhost"],
    ], rows
  end

  test "return the additional committers for an enterprise filtered by repo_ids" do
    org = create(:organization)
    repo_id = 2

    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetCommittersResponse.new(committers: [
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 2, login: "user-2", email: "user-2@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 3, login: "user-3", email: "user-3@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
    ]))

    business = GitHub.global_business ? GitHub.global_business : create(:business, organizations: [org])
    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_committers_for_business).returns(response)

    title_row, *rows = CSV.parse(Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: business, committer_type: :ADDITIONAL_COMMITTERS, repository_ids: [repo_id]))

    assert_equal ["User login", "Organization / repository", "Last pushed date", "Last pushed email"], title_row
    assert_same_elements [
      ["user-2", "org-1/test-2", "2023-06-13", "user-2@localhost"],
      ["user-3", "org-1/test-2", "2023-06-13", "user-3@localhost"],
    ], rows
  end

  test "return the maximum committers for an enterprise feature flag" do
    org = create(:organization)
    repo_id = 2

    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetCommittersResponse.new(committers: [
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 1, login: "user-1", email: "user-1@localhost", repository_id: 1, repository_nwo: "org-1/test-1", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 2, login: "user-2", email: "user-2@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 3, login: "user-3", email: "user-3@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 4, login: "user-4", email: "user-4@localhost", repository_id: 3, repository_nwo: "org-2/test-1", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
    ]))

    business = GitHub.global_business ? GitHub.global_business : create(:business, organizations: [org])
    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_committers_for_business).returns(response)

    title_row, *rows = CSV.parse(Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: business, committer_type: :MAXIMUM_COMMITTERS))

    assert_equal ["User login", "Organization / repository", "Last pushed date", "Last pushed email"], title_row
    assert_same_elements [
      ["user-1", "org-1/test-1", "2023-06-13", "user-1@localhost"],
      ["user-2", "org-1/test-2", "2023-06-13", "user-2@localhost"],
      ["user-3", "org-1/test-2", "2023-06-13", "user-3@localhost"],
      ["user-4", "org-2/test-1", "2023-06-13", "user-4@localhost"],
    ], rows
  end

  test "return the maximum committers for an enterprise filtered by repo_ids" do
    org = create(:organization)
    repo_id = 2

    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetCommittersResponse.new(committers: [
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 2, login: "user-2", email: "user-2@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
      ::Turboghas::Proto::GetCommittersResponse::Committer.new(id: 3, login: "user-3", email: "user-3@localhost", repository_id: 2, repository_nwo: "org-1/test-2", pushed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2023-06-13").to_i)),
    ]))

    business = GitHub.global_business ? GitHub.global_business : create(:business, organizations: [org])
    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_committers_for_business).returns(response)

    title_row, *rows = CSV.parse(Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: business, committer_type: :MAXIMUM_COMMITTERS, repository_ids: [repo_id]))

    assert_equal ["User login", "Organization / repository", "Last pushed date", "Last pushed email"], title_row
    assert_same_elements [
      ["user-2", "org-1/test-2", "2023-06-13", "user-2@localhost"],
      ["user-3", "org-1/test-2", "2023-06-13", "user-3@localhost"],
    ], rows
  end
end
