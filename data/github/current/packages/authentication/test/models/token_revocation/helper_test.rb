# typed: true
# frozen_string_literal: true

require "test_helper"

class TokenRevocationHelperTest < GitHub::TestCase
  include DogstatsTestHelpers
  include AuthndClientTestHelpers

  fixtures do
    @user = create :user
    @pat = create :personal_token_oauth_access, user: @user, scopes: %w(user)
    @fg_pat_access = create :user_programmatic_access, owner: @user
    stub_authnd_programmatic_access_issue_token
    @fg_pat_token = ProgrammaticAccessTokens.domain.generate(@fg_pat_access.user_id, @fg_pat_access.id).value
    stub_authnd_programmatic_access_token(@fg_pat_access, @fg_pat_token)
  end

  setup do
    enable_feature_flag(:credential_revocation_api)
    enable_feature_flag(:credential_revocation_api_mailers)
    ActionMailer::Base.deliveries.clear

    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  context "#notify_owner_of_revoked_credential" do
    test "does not notify if FF is disabled" do
      disable_feature_flag(:credential_revocation_api)

      assert_no_difference "ActionMailer::Base.deliveries.size" do
        TokenRevocation::Helper.notify_owner_of_revoked_credential(@user, @pat.description, TokenRevocation::Helper::PAT_CREDENTIAL)
      end
    end

    test "does not notify if user is nil" do
      assert_no_difference "ActionMailer::Base.deliveries.size" do
        TokenRevocation::Helper.notify_owner_of_revoked_credential(nil, @pat.description, TokenRevocation::Helper::PAT_CREDENTIAL)
      end

      assert_dogstats_increment("revoked_credential.notify", tags: ["result:failed", "reason:missing_owner", "type:PERSONAL_ACCESS_TOKEN"])
    end

    test "does not notify if credential type is not supported" do
      assert_no_difference "ActionMailer::Base.deliveries.size" do
        TokenRevocation::Helper.notify_owner_of_revoked_credential(@user, nil, :INVALID)
      end

      assert_dogstats_increment("revoked_credential.notify", tags: ["result:failed", "reason:invalid_type", "type:INVALID"])
      refute_dogstats_increment("revoked_credential.notify", tags: ["result:queued", "type:INVALID"])
    end

    test "notifies user of revoked personal access token" do
      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          TokenRevocation::Helper.notify_owner_of_revoked_credential(@user, @pat.description, TokenRevocation::Helper::PAT_CREDENTIAL)
        end
        mail = ActionMailer::Base.deliveries.last
        assert_equal mail.subject, "[GitHub] Your personal access token, #{@pat.description}, has been revoked"
      end

      assert_dogstats_increment("revoked_credential.notify", tags: ["result:queued", "type:#{TokenRevocation::Helper::PAT_CREDENTIAL}"])
    end

    test "notifies user of revoked fine grained personal access token" do
      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          TokenRevocation::Helper.notify_owner_of_revoked_credential(@user, @fg_pat_access.name, TokenRevocation::Helper::FG_PAT_CREDENTIAL)
        end
        mail = ActionMailer::Base.deliveries.last
        assert_equal mail.subject, "[GitHub] Your fine-grained personal access token, #{@fg_pat_access.name}, has been revoked"
      end
      assert_dogstats_increment("revoked_credential.notify", tags: ["result:queued", "type:#{TokenRevocation::Helper::FG_PAT_CREDENTIAL}"])
    end
  end

  context "#credential_revocation_enabled?" do
    test "returns false if none of the FFs are enabled" do
      disable_feature_flag(:credential_revocation_api)
      disable_feature_flag(:credential_revocation_api_review_lab)

      refute TokenRevocation::Helper.credential_revocation_enabled?
    end

    test "returns false if the review lab FF is enabled and not in review lab env" do
      disable_feature_flag(:credential_revocation_api)
      enable_feature_flag(:credential_revocation_api_review_lab)
      GitHub.stubs(:review_lab?).returns(false)
      refute TokenRevocation::Helper.credential_revocation_enabled?
    end

    test "returns true if the main FF is enabled" do
      enable_feature_flag(:credential_revocation_api)
      disable_feature_flag(:credential_revocation_api_review_lab)

      assert TokenRevocation::Helper.credential_revocation_enabled?
    end

    test "returns true if the review lab FF is enabled and in review lab env" do
      disable_feature_flag(:credential_revocation_api)
      enable_feature_flag(:credential_revocation_api_review_lab)
      GitHub.stubs(:review_lab?).returns(true)
      assert TokenRevocation::Helper.credential_revocation_enabled?
    end
  end
end
