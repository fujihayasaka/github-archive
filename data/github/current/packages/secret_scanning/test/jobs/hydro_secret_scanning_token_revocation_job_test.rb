# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Jobs
  class HydroSecretScanningTokenRevocationJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers

    setup do
      @user = create(:user)
      @gist = create(:gist, user: @user, public: true)
      @org = create(:organization, admin: @user)
      @repo = create(:public_repository, owner: @org)
      @priv_repo = create(:private_repository, owner: @org)
      @outside_collaborator = create(:user)
      @repo.add_member(@outside_collaborator)
      @rando = create(:user)
    end

    setup do
      ActionMailer::Base.deliveries.clear
    end

    test "sends access token leaked email for a gist" do
      message = {
        token_user_id: @user.id,
        repository_type: :GIST,
        repository_id: @gist.id,
        url: "https://example.com"
      }

      SecretScanningMailer.expects(:personal_access_token_leaked)
        .with(
          @gist,
          @user,
          :GIST,
          "https://example.com",
          equals({ token_type: "GITHUB_TOKEN_V2", key_name: nil }))
        .once.returns(stub(deliver_later: nil))

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.GithubTokenRevocationEvent", queue: "hydro_secret_scanning_token_revocation")
    end

    test "sends access token leaked email for a public repo" do
      message = {
        token_user_id: @user.id,
        repository_type: :REPOSITORY,
        repository_id: @repo.id,
        url: "https://example.com"
       }

      SecretScanningMailer.expects(:personal_access_token_leaked)
        .with(
          @repo,
          @user,
          :UNKNOWN_SOURCE,
          "https://example.com",
          equals({ token_type: "GITHUB_TOKEN_V2", key_name: nil }))
        .once.returns(stub(deliver_later: nil))

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.GithubTokenRevocationEvent", queue: "hydro_secret_scanning_token_revocation")
    end

    test "does nothing with an unknown user" do
      message = {
        token_user_id: 100000
      }

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.GithubTokenRevocationEvent", queue: "hydro_secret_scanning_token_revocation")
      assert_equal 0, ActionMailer::Base.deliveries.length
    end

    test "does nothing with an unknown repo/gist" do
      message = {
        token_user_id: @user.id,
        repository_type: :REPOSITORY,
        repository_id: 100000
       }

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.GithubTokenRevocationEvent", queue: "hydro_secret_scanning_token_revocation")
      assert_equal 0, ActionMailer::Base.deliveries.length

      message = {
        token_user_id: @user.id,
        repository_type: :GIST,
        repository_id: 100000
      }

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.GithubTokenRevocationEvent", queue: "hydro_secret_scanning_token_revocation")
      assert_equal 0, ActionMailer::Base.deliveries.length
    end
  end
end
