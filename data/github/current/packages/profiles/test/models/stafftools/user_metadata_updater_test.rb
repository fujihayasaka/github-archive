# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsUserMetadataUpdaterTest < GitHub::TestCase
  include HydroTestHelpers

  setup do
    skip if GitHub.enterprise?
  end

  context "#trigger_recalculation!" do
    context "for all attributes" do
      test "instruments the recalculation" do
        user_metadata = create(:user_metadata)
        user = user_metadata.user
        updater = Stafftools::UserMetadataUpdater.new(user: user)

        updater.trigger_recalculation!(attribute_to_recalculate: "all")
        message = {
          actor: Hydro::EntitySerializer.user(user),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          target_user: Hydro::EntitySerializer.user(user),
          target_stream_processor: :ALL,
        }

        assert_hydro_published(message, schema: "github.user_metadata.v1.Recalculation")
        assert_hydro_messages(count: 1, schema: "github.user_metadata.v1.Recalculation")
      end
    end

    context "for a specific attribute" do
      test "instruments the recalculation" do
        user_metadata = create(:user_metadata)
        user = user_metadata.user
        updater = Stafftools::UserMetadataUpdater.new(user: user)

        updater.trigger_recalculation!(attribute_to_recalculate: "followers_count")
        message = {
          actor: Hydro::EntitySerializer.user(user),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          target_user: Hydro::EntitySerializer.user(user),
          target_stream_processor: :FOLLOWS,
        }

        assert_hydro_published(message, schema: "github.user_metadata.v1.Recalculation")
        assert_hydro_messages(count: 1, schema: "github.user_metadata.v1.Recalculation")
      end
    end
  end

  context "#toggle!" do
    test "it changes the attribute to false when it's true" do
      user_metadata = create(:user_metadata, has_sponsoring_badge: true)
      user = user_metadata.user
      updater = Stafftools::UserMetadataUpdater.new(user: user)

      updater.toggle!(attribute_to_toggle: "has_sponsoring_badge")

      refute_predicate user_metadata, :has_sponsoring_badge
    end

    test "it changes the attribute to true when it's false" do
      user_metadata = create(:user_metadata, has_sponsoring_badge: false)
      user = user_metadata.user
      updater = Stafftools::UserMetadataUpdater.new(user: user)

      updater.toggle!(attribute_to_toggle: "has_sponsoring_badge")

      assert_predicate user_metadata, :has_sponsoring_badge
    end
  end
end
