# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RecognizeSocialAccountJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @profile = create(:profile)
  end

  teardown do
    SocialAccounts::NodeinfoProbe.faraday_conf_block = -> (conn) { conn.adapter(Faraday.default_adapter) }
  end

  if GitHub.nodeinfo_probe_enabled?
    test "updates social accounts on profiles when Nodeinfo recognition has succeeded" do
      SocialAccounts::NodeinfoProbe.faraday_conf_block = lambda do |faraday|
        faraday.adapter(:test) do |stub|
          stub.get("https://somehost.com/.well-known/nodeinfo") do
            doc = {
              "links" => [
                {
                  "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                  "href" => "https://somehost.com/nodeinfo/2.1",
                }
              ]
            }
            [200, { "Content-Type" => "application/json" }, doc.to_json]
          end
          stub.get("https://somehost.com/nodeinfo/2.1") do
            doc = { "software" => { "name" => "mastodon" } }
            [200, { "Content-Type" => "application/json" }, doc.to_json]
          end
        end
      end

      twitch_account = create(:social_account_twitch)
      @profile.social_accounts = [create(:social_account, url: "https://somehost.com/@someuser"), twitch_account]
      @profile.save!

      RecognizeSocialAccountJob.perform_now(@profile.id)

      @profile.reload

      assert_equal [create(:social_account_mastodon, url: "https://somehost.com/@someuser"), twitch_account],
        @profile.social_accounts
    end
  else
    test "does not perform Nodeinfo recognition" do
      SocialAccounts::NodeinfoProbe.faraday_conf_block = lambda do |faraday|
        faraday.adapter(:test) {}
      end

      account = create(:social_account, url: "https://somehost.com/@someuser")
      @profile.social_accounts = [account]
      @profile.save!

      RecognizeSocialAccountJob.perform_now(@profile.id)

      @profile.reload
      assert_equal [account], @profile.social_accounts
    end
  end

  test "no-op when no additional recognition succeeds" do
    SocialAccounts::NodeinfoProbe.faraday_conf_block = lambda do |faraday|
      faraday.adapter(:test) do |stub|
        stub.get("https://not-mastodon.com/.well-known/nodeinfo") do
          [404, { "Content-Type" => "text/plain" }, "nah"]
        end
      end
    end

    account_0 = create(:social_account, url: "https://the-new-hotness.com/accounts/monalisa")
    account_1 = create(:social_account_linkedin)
    account_2 = create(:social_account, url: "https://not-mastodon.com/@monalisa")
    @profile.social_accounts = [account_0, account_1, account_2]
    @profile.save!

    RecognizeSocialAccountJob.perform_now(@profile.id)

    @profile.reload

    assert_equal [account_0, account_1, account_2], @profile.social_accounts
  end

  test "retries on dirty exits" do
    assert_retry_on_dirty_exit job: RecognizeSocialAccountJob, args: [@profile.id]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: RecognizeSocialAccountJob, args: [@profile.id]
  end

  test "retries when replication lag causes profiles to not be found" do
    assert_enqueued_with(job: RecognizeSocialAccountJob, args: [-1]) do
      RecognizeSocialAccountJob.perform_now(-1)
    end
  end
end
