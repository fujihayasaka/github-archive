# typed: true
# frozen_string_literal: true

require "test_helper"

class UserOrcidDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @orcid_record = create(:orcid_record, user: @user)

    @user_recordless = create(:user)
  end

  context "has_orcid_record?" do
    test "returns false if UserMetadata does not exist" do
      assert_nil @user_recordless.user_metadata
      refute_predicate @user_recordless, :has_orcid_record?
    end

    test "checks UserMetadata if record exists" do
      refute_nil @user.user_metadata
      assert_predicate @user.user_metadata, :has_orcid_record?
      @user.reset_orcid_record

      assert_no_queries do
        assert_predicate @user, :has_orcid_record?
      end
    end

    test "always returns false for non-User subclasses" do
      non_users = [
        create(:organization),
        create(:bot),
        create(:user_programmatic_access).bot,
        create(:mannequin),
      ]

      non_users.each do |userlike|
        assert_no_queries do
          refute_predicate userlike, :has_orcid_record?
        end
      end
    end
  end

  context "display_orcid_id_on_profile setting" do
    test "defaults to true" do
      assert_predicate @user, :display_orcid_id_on_profile?
      assert_predicate @user_recordless, :display_orcid_id_on_profile?
    end

    test "may be set to false" do
      @user.display_orcid_id_on_profile = false
      refute_predicate @user, :display_orcid_id_on_profile?
    end

    test "publishes a Hydro event on change", skip_enterprise: true do
      GitHub.context.push(user_agent: "test agent")

      @user.display_orcid_id_on_profile = false
      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(@user),
        display_on_profile: false,
      }
      assert_hydro_published(message, schema: "github.v1.OrcidDisplayPreferenceChange")
      assert_hydro_messages(count: 1, schema: "github.v1.OrcidDisplayPreferenceChange")
    end

    test "does not publish a Hydro event when left as the default", skip_enterprise: true do
      # true is the default value
      @user.display_orcid_id_on_profile = true

      refute_hydro_messages(schema: "github.v1.OrcidDisplayPreferenceChange")
    end

    test "does not publish a Hydro event when unchanged", skip_enterprise: true do
      @user.display_orcid_id_on_profile = false
      reset_hydro

      @user.display_orcid_id_on_profile = false

      refute_hydro_messages(schema: "github.v1.OrcidDisplayPreferenceChange")
    end
  end
end
