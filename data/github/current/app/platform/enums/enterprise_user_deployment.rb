# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseUserDeployment < Platform::Enums::Base
      description "The possible GitHub Enterprise deployments where this user can exist."

      value "CLOUD", "The user is part of a GitHub Enterprise Cloud deployment.", value: "cloud"
      value "SERVER", "The user is part of a GitHub Enterprise Server deployment.", value: "server"
    end
  end
end
