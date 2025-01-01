# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroPushJobFlagsTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  test ".enabled_for_repo" do
    Repositories::HydroPushJobFlags.stub_const(:FLAGS, %w[hydro_push_flag_1 hydro_push_flag_2]) do
      if TestEnv.test_all_features?
        assert_equal Repositories::HydroPushJobFlags::FLAGS, Repositories::HydroPushJobFlags.enabled_for_repo(@repo)
      else
        GitHub.flipper[:hydro_push_flag_1].enable(@repo)

        assert_equal %w[hydro_push_flag_1], Repositories::HydroPushJobFlags.enabled_for_repo(@repo)
      end
    end
  end

  test "#enabled? filters flags based on internal list and enablement" do
    Repositories::HydroPushJobFlags.stub_const(:FLAGS, %w[hydro_push_flag_1 hydro_push_flag_2]) do
      flags = Repositories::HydroPushJobFlags.new(%w[hydro_push_flag_1 hydro_push_flag_2])

      assert_equal true, flags.enabled?("hydro_push_flag_1")
      assert_equal true, flags.enabled?("hydro_push_flag_2")

      assert_equal false, flags.enabled?("some_random_flag_name")
    end
  end
end
