# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AppInstallationOrderField < Platform::Enums::Base
      description "Properties by which app installation connections can be ordered."

      visibility :internal

      value "CREATED_AT", "Order app installations by creation time.", value: "created_at"
      value "UPDATED_AT", "Order app installations by update time.", value: "updated_at"
    end
  end
end
