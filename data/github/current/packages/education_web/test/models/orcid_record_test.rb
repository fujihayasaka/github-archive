# typed: true
# frozen_string_literal: true

require "test_helper"

class OrcidRecordTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
  end

  setup do
    @original_orcid_host = GitHub.orcid_host
  end

  teardown do
    GitHub.orcid_host = @original_orcid_host
  end

  context "validations" do
    test "factory creates a valid one by default" do
      assert_predicate build(:orcid_record), :valid?
    end

    test "requires a non-null user association" do
      record = build(:orcid_record, user: nil)
      refute_predicate record, :valid?
    end

    test "requires a present identifier" do
      record = build(:orcid_record, identifier: "")
      refute_predicate record, :valid?
    end
  end

  context "callbacks" do
    test "updates user_metadata on associated user when created" do
      metadata = create(:user_metadata, user: @user)
      refute_predicate metadata, :has_orcid_record?
      create(:orcid_record, user: @user)
      assert_predicate metadata, :has_orcid_record?
    end

    test "updates user_metadata on associated user when destroyed" do
      metadata = create(:user_metadata, user: @user)
      orcid_record = create(:orcid_record, user: @user)
      assert_predicate metadata, :has_orcid_record?
      orcid_record.destroy!
      refute_predicate metadata, :has_orcid_record?
    end

    test "creates user_metadata if it does not exist" do
      @user.user_metadata&.destroy!
      create(:orcid_record, user: @user)
      refute_nil @user.user_metadata
      assert_predicate @user.user_metadata, :has_orcid_record?
    end

    test "does not create user_metadata just to set a default value" do
      orcid_record = create(:orcid_record, user: @user)
      @user.user_metadata = nil
      orcid_record.destroy!
      assert_nil @user.reload.user_metadata
    end

    test "does not fail when associated user itself is being destroyed" do
      orcid_record = create(:orcid_record, user: @user)
      @user.destroy!
      refute OrcidRecord.find_by(id: orcid_record.id)
    end
  end

  context "#profile_url" do
    test "generates the URL of the ORCID profile" do
      GitHub.orcid_host = "example.com"
      record = create(:orcid_record, identifier: "1111-2222-3333-4444")

      assert_equal "https://example.com/1111-2222-3333-4444", record.profile_url
    end

    test "escapes identifier characters not allowed in a URL path" do
      # This shouldn't actually happen because we get identifiers directly from the ORCID API.
      GitHub.orcid_host = "sandbox.orcid.com"
      record = create(:orcid_record, identifier: "a/b?c=1@d=e")

      assert_equal "https://sandbox.orcid.com/a%2Fb%3Fc%3D1%40d%3De", record.profile_url
    end
  end

  context "Hydro events", skip_enterprise: true do
    test "publishes OrcidRecordCreate when created" do
      GitHub.context.push(actor_ip: "3ffe:505:2::1")
      GitHub.context.push(user_agent: "test agent")

      create(:orcid_record, user: @user, identifier: "0000-1111-2222-3333")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@user),
        identifier: "0000-1111-2222-3333",
      }
      assert_hydro_published(message, schema: "github.v1.OrcidRecordCreate")
      assert_hydro_messages(count: 1, schema: "github.v1.OrcidRecordCreate")
    end

    test "publishes OrcidRecordDestroy when destroyed" do
      GitHub.context.push(actor_ip: "3ffe:505:2::1")
      GitHub.context.push(user_agent: "test agent")
      record = create(:orcid_record, user: @user, identifier: "3333-2222-1111-0000")
      reset_hydro

      record.destroy!

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@user),
        identifier: "3333-2222-1111-0000",
      }
      assert_hydro_published(message, schema: "github.v1.OrcidRecordDestroy")
      assert_hydro_messages(count: 1, schema: "github.v1.OrcidRecordDestroy")
    end
  end
end
