# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetBillingDetails
        include Scientist

        attr_reader :repository

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          database_id = Platform::Helpers::NodeIdentification.from_global_id(request.repository_id.global_id).last

          @repository = Repositories.domain.by_id(database_id.to_i)
        end

        def call
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository
          return Twirp::Error.not_found("repository owner does not exist") unless repository.owner

          actions_permission = Billing::ActionsPermission.new(repository.owner)

          {
            is_actions_usage_allowed: actions_permission.usage_allowed?(public: repository.public?),
            is_actions_storage_allowed: actions_permission.storage_allowed?(public: repository.public?),
            is_owner_spammy: repository.owner.spammy?,
          }
        end
      end
    end
  end
end
