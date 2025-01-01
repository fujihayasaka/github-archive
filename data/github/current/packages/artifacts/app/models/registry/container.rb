# typed: true
# frozen_string_literal: true

# This PORO model is a representation of a container. A container is a package
# stored and managed by the `registry-metadata` service.
module Registry
  class Container

    include Permissions::Attributes::Wrapper
    self.permissions_wrapper_class = Permissions::Attributes::RegistryContainer

    attr_reader :id, :owner

    def initialize(opts = {})
      @id = opts["id"]
      @owner = User.find_by(login: opts["namespace"])
    end

    def user_role_target_type
      "Package"
    end
  end
end
