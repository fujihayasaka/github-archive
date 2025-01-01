# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsAcceptSocialAccountParametersTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @profile = create(:profile, user: @user, social_accounts: [
      create(:social_account_twitter, url: "https://twitter.com/monalisa"),
    ])
  end

  def make_params(**values)
    ActionController::Parameters.new(values)
  end

  test "noop without :profile_social_accounts" do
    SocialAccounts::AcceptSocialAccountParameters.call(user: @user, params: make_params)

    assert_equal [create(:social_account_twitter, url: "https://twitter.com/monalisa")],
      @user.profile_social_accounts
  end

  context "with :profile_social_accounts" do
    test "writes social accounts" do
      SocialAccounts::AcceptSocialAccountParameters.call(user: @user, params: make_params(
        profile_social_accounts: [
          { key: "mastodon", url: "https://mastodon.social/@monalisa" },
          { key: "twitter", url: "https://twitter.com/incoming" },
        ],
      ))

      assert_equal 2, @user.profile_social_accounts.size
      assert_equal "mastodon", @user.profile_social_accounts[0].key
      assert_equal "https://mastodon.social/@monalisa", @user.profile_social_accounts[0].url
      assert_equal "twitter", @user.profile_social_accounts[1].key
      assert_equal "https://twitter.com/incoming", @user.profile_social_accounts[1].url
    end

    test "writes social accounts and ignores blank URLs" do
      SocialAccounts::AcceptSocialAccountParameters.call(user: @user, params: make_params(
        profile_social_accounts: [
          { key: "twitter", url: "  " },
          { key: "mastodon", url: "https://mastodon.social/@monalisa" },
        ],
      ))

      assert_equal 1, @user.profile_social_accounts.size
      assert_equal "mastodon", @user.profile_social_accounts[0].key
      assert_equal "https://mastodon.social/@monalisa", @user.profile_social_accounts[0].url
    end

    test "preserves metadata on existing social accounts that are still present" do
      @user.profile_social_accounts = [
        create(:social_account_mastodon,
          url: "https://mastodon.social/@monalisa",
          meta: { "some_key" => "some_value" }),
      ]

      SocialAccounts::AcceptSocialAccountParameters.call(user: @user, params: make_params(
        profile_social_accounts: [
          { key: "mastodon", url: "https://mastodon.social/@monalisa" },
          { key: "linkedin", url: "https://www.linkedin.com/in/mona-lisa" },
        ],
      ))

      assert_equal 2, @user.profile_social_accounts.size

      mastodon_account = @user.profile_social_accounts.first
      assert_equal "mastodon", mastodon_account.key
      assert_equal "https://mastodon.social/@monalisa", mastodon_account.url
      assert_equal({ "some_key" => "some_value" }, mastodon_account.meta)

      linkedin_account = @user.profile_social_accounts.second
      assert_equal "linkedin", linkedin_account.key
      assert_equal "https://www.linkedin.com/in/mona-lisa", linkedin_account.url
      assert_equal({}, linkedin_account.meta)
    end

    test "performs server-side recognition of general accounts" do
      SocialAccounts::AcceptSocialAccountParameters.call(user: @user, params: make_params(
        profile_social_accounts: [
          { key: "generic", url: "https://www.instagram.com/missed-me-somehow" },
        ],
      ))

      assert_equal [create(:social_account_instagram, url: "https://www.instagram.com/missed-me-somehow")],
        @user.profile_social_accounts
    end

    if GitHub.nodeinfo_probe_enabled?
      test "schedules a job to perform expensive recognition of social accounts" do
        assert_enqueued_with(job: RecognizeSocialAccountJob, args: [@profile.id]) do
          SocialAccounts::AcceptSocialAccountParameters.call(user: @user, params: make_params(
            profile_social_accounts: [
              { key: "generic", url: "https://mastodon.social/@nojs" },
            ],
          ))
        end
      end
    else
      test "does not schedule a job to perform expensive recognition of social accounts" do
        assert_no_enqueued_jobs(only: RecognizeSocialAccountJob) do
          SocialAccounts::AcceptSocialAccountParameters.call(user: @user, params: make_params(
            profile_social_accounts: [
              { key: "generic", url: "https://mastodon.social/@nojs" },
            ],
          ))
        end
      end
    end
  end
end
