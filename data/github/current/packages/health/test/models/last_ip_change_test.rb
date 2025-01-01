# typed: true
# frozen_string_literal: true

require "test_helper"

class LastIpChangeTest < GitHub::TestCase
  include HydroTestHelpers

  test "instruments last_ip change and publishes to hydro" do
    GitHub.stubs(:hydro_enabled?).returns(true)
    now = Time.now.beginning_of_day

    Timecop.freeze(now) do
      user = create(:user, last_ip: "4.3.2.1")

      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub.context.push(user_agent: "test agent")

      user.update(last_ip: "1.2.3.4")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(user),
        previous_ip: Hydro::EntitySerializer.ip_address("4.3.2.1"),
        current_ip: Hydro::EntitySerializer.ip_address("1.2.3.4"),
      }

      assert_hydro_published(message, schema: "github.v1.UserIPAddressUpdate")
    end
  end
end
