# typed: true
# frozen_string_literal: true

module Octoshift
  class MigrationSource
    include GitHub::Relay::GlobalIdentification
    extend Forwardable

    def_delegators :@connector, :id, :name, :url, :owner_id, :owner_login
    def_delegator :@connector, :connector_instance_type, :type

    def initialize(connector)
      @connector = connector
    end

    def platform_type_name
      "MigrationSource"
    end

    def async_owner
      Platform::Loaders::ActiveRecord.load(::User, owner_id)
    end

    def ==(other)
      self.class == other.class && id == other.id
    end
  end
end
