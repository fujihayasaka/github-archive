# typed: true
# frozen_string_literal: true

require "graphql/client/view_module"
require "view_module_patch"

GraphQL::Client::ViewModule.prepend(ViewModulePatch)

module Views
  extend GraphQL::Client::ViewModule

  self.path = File.join(Rails.root, "app/views").freeze
  self.client = PlatformHelper::PlatformClient
end
