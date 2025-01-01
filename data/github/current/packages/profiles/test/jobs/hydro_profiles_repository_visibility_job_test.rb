# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroProfilesRepositoryVisibilityJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  test "it works" do
    repo = create(:public_repository)
    user_profile = create(:profile, user: repo.owner)
    ProfilePin.create!(pinned_item_type: "Repository", pinned_item_id: repo.id, profile_id: user_profile.id)
    # skip ActiveRecord callbacks
    repo.update_column :public, false

    message = {
      repository_id: repo.id,
      actor_id: repo.owner.id,
      new_visibility: Repository::PRIVATE_VISIBILITY,
      old_visibility: Repository::PUBLIC_VISIBILITY,
    }

    assert_changes -> { ProfilePin.count }, -1 do
      perform_hydro_message_job(message, schema: "github.repositories.v1.VisibilityChanged", queue: "hydro_profiles_repository_visibility")
    end
  end
end
