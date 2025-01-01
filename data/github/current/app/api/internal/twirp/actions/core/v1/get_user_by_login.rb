# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions::Core::V1
  class GetUserByLogin
    include Api::Internal::Twirp::Actions::Core::V1::ActorsDependency

    attr_reader :req

    def self.call(request)
      new(request).call
    end

    def initialize(request)
      @req = request
    end

    def call
      return Twirp::Error.invalid_argument("missing login", argument: "login") if req.login.blank?

      if GitHub.multi_tenant_enterprise? && !GitHub::CurrentTenant.get.present?
        return Twirp::Error.failed_precondition("Tenant must be set in header")
      end

      user = User.find_by_login(req.login)

      return Twirp::Error.not_found("user does not exist", argument: "login") unless user

      {
        id: user.id,
        global_id: { global_id: get_global_id(user) },
      }
    end
  end
end
