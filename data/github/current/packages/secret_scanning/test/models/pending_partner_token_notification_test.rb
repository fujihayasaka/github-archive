# typed: true
# frozen_string_literal: true

require "test_helper"

class PendingPartnerTokenNotificationTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  context "validation" do
    test "requires a repository_id" do
      token = PendingPartnerTokenNotification.new(repository_id: nil)

      refute_predicate token, :valid?
      refute_empty token.errors[:repository_id]
    end

    test "requires a token type" do
      token = PendingPartnerTokenNotification.new(repository_id: @repo.id, token_type: "")

      refute_predicate token, :valid?
      refute_empty token.errors[:token_type]
    end

    test "requires a path" do
      token = PendingPartnerTokenNotification.new(repository_id: @repo.id)

      refute_predicate token, :valid?
      refute_empty token.errors[:path]
    end

    test "requires a commit_oid" do
      token = PendingPartnerTokenNotification.new(repository_id: @repo.id)

      refute_predicate token, :valid?
      refute_empty token.errors[:commit_oid]
    end

    test "requires a blob_oid" do
      token = PendingPartnerTokenNotification.new(repository_id: @repo.id)

      refute_predicate token, :valid?
      refute_empty token.errors[:blob_oid]
    end

    test "defaults to unknown repo type when not passed in" do
      token = PendingPartnerTokenNotification.new(repository_id: @repo.id)

      assert_equal "unknown", token.repository_type
    end

    test "requires a valid blob id of 40 characters" do
      token = PendingPartnerTokenNotification.new(repository_id: @repo.id, blob_oid: "short_blob")

      refute_predicate token, :valid?
      refute_empty token.errors[:blob_oid]

      token = PendingPartnerTokenNotification.new(repository_id: @repo.id, blob_oid: "toooooooooooooooooooooooo_looooooooong_blooob")

      refute_predicate token, :valid?
      refute_empty token.errors[:blob_oid]
    end
  end

  context ".create_from_failed_token!" do
    test "finds or creates the token entry for the token repo id and token object" do
      token = GitHub::TokenScanning::FoundToken.new(**
        {
          type: "ACME",
          token: "asdf",
          url: "https://acme.com/asdf",
          report_url: "https://acme.com/",
          blob: "dhjghfg83884784brgnbfngbf8n4tb4jmnfgb32f",
          commit: "dhjghfg83884784brgnbfngbf8n4tb4jmnfgb32f",
          path: "abc/READMe.md",
          start_line: 4,
          end_line: 4,
          start_column: 54,
          end_column: 79,
        }
      )

      token1 = assert_difference("PendingPartnerTokenNotification.count", 1) do
        PendingPartnerTokenNotification.create_from_failed_token!(@repo, token)
      end

      refute_nil token1

      token2 = assert_no_difference("PendingPartnerTokenNotification.count") do
        PendingPartnerTokenNotification.create_from_failed_token!(@repo, token)
      end

      assert_equal token1, token2
      assert_equal "repository", token1.repository_type
    end

    test "runs validations" do
      token =  GitHub::TokenScanning::FoundToken.new(**
        {
          type: "ACME",
          token: "asdf",
          url: "https://acme.com/asdf",
          report_url: "https://acme.com/",
        }
      )

      assert_raises(ActiveRecord::RecordInvalid) do
        PendingPartnerTokenNotification.create_from_failed_token!(@repo, token)
      end
    end
  end
end
