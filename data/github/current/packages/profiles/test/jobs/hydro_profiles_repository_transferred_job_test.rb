# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroProfilesRepositoryTransferredJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @new = create(:organization)
    @repo = create(:repository, owner: @org)
  end

  setup do
    @message = {
      repository_id: @repo.id,
      new_owner: Hydro::EntitySerializer.user(@new),
      previous_name: @repo.name,
      new_name: @repo.name,
      new_visibility: "PUBLIC",
      actor_id: @user.id,
    }
  end

  test "it unpins when previous owner was an org" do
    message = @message.merge(previous_owner: Hydro::EntitySerializer.user(@org))

    ProfilePinner.expects(:unpin).once

    perform_hydro_message_job(message, schema: "github.repositories.v1.Transferred", queue: "hydro_profiles_repository_transferred")

  end

  test "it does not unpin when previous owner was a user" do
    message = @message.merge(previous_owner: Hydro::EntitySerializer.user(@user))

    ProfilePinner.expects(:unpin).never

    perform_hydro_message_job(message, schema: "github.repositories.v1.Transferred", queue: "hydro_profiles_repository_transferred")

  end
end
