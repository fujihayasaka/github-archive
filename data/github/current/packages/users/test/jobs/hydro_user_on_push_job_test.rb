# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroUserOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  fixtures do
    @mojombo = create(:user, login: "mojombo",  plan: "medium")
    @grit    = create(:repository, name: "github", owner: @mojombo, from_example: :mojombo_grit)
  end

  if Interaction.enabled?
    context "interaction tracking" do
      test "tracks push for user when push is created" do
        message = {
          ref_updates: [{ ref: "refs/heads/master", before: "4c8124ffcf4039d292442eeccabdeca5af5c5017", after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425" }],
          repository_id: @grit.id,
          pusher: @mojombo.login,
          pushed_at: Time.now
        }
        interaction = Interaction.for_user(@mojombo)
        assert_nil interaction.last_pushed_at
        assert_difference "interaction.pushes" do
          perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_user_on_push")

          interaction.reload
        end
        assert interaction.last_pushed_at?
      end
    end
  end
end
