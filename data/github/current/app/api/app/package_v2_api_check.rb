# typed: false
# frozen_string_literal: true

module Api::App::PackageV2ApiCheck
  def disallow_package_v2(events)
    if events.include?("package_v2")
      deliver_error! 422,
        message: "As of June 2021, the `package_v2` event can no longer be subscribed to. Please use the `package` event instead."
    end
  end
end
