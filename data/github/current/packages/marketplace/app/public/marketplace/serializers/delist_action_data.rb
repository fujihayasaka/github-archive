# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    class DelistActionData
      include T::Helpers
      include HydroHelper

      sig { returns(RepositoryAction) }
      attr_reader :repository_action

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(String) }
      attr_reader :request_url

      sig { params(repository_action: RepositoryAction, current_user: T.nilable(User), request_url: String).void }
      def initialize(repository_action, current_user, request_url)
        @repository_action = repository_action
        @current_user = current_user
        @request_url = request_url
      end

      sig { returns(Marketplace::Types::SerializedDelistActionData) }
      def call
        {
          hydroAttrs: hydro_click_tracking_attributes("marketplace.action.delist", hydro_payload),
          repoAdminableByViewer: repo_viewer_can_administer?
        }
      end

      private

      sig { returns(T::Hash[Symbol, String]) }
      def hydro_payload
        {
          repository_action_id: repository_action.global_relay_id,
          source_url: request_url,
          location: "actions#show"
        }
      end

      sig { returns(T::Boolean) }
      def repo_viewer_can_administer?
        repository = repository_action.repository
        return false unless current_user && repository

        repository.adminable_by?(current_user)
      end
    end
  end
end
