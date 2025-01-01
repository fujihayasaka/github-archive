# typed: strict
# frozen_string_literal: true

module Marketplace
  module Payloads
    class ShowAction
      include GitHub::Memoizer
      include ::Search::RepositoryActionIconHelper
      include UrlHelpers

      sig { returns(RepositoryAction) }
      attr_reader :repository_action

      sig { returns(T.nilable(String)) }
      attr_reader :selected_version

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(String) }
      attr_reader :request_url

      delegate :repository, to: :repository_action, private: true

      sig { params(repository_action: RepositoryAction, selected_version: T.nilable(String), current_user: T.nilable(User), request_url: String).void }
      def initialize(repository_action:, selected_version:, current_user:, request_url:)
        @repository_action = repository_action
        @selected_version = selected_version
        @current_user = current_user
        @request_url = request_url
      end

      sig do
        returns({
          action: Marketplace::Types::SerializedActionListing,
          readmeHtml: T.nilable(String),
          helpUrl: String,
          repository: Marketplace::Types::SerializedRepository,
          delistActionData: Marketplace::Types::SerializedDelistActionData
        })
      end
      def call
        {
          action: Marketplace::Serializers::Action.serialize_model(repository_action),
          readmeHtml: readme_html,
          helpUrl: "#{GitHub.help_url}/articles/about-readmes/",
          repository: Marketplace::Serializers::Repository.new(repository: repository, current_user: current_user).call,
          delistActionData: Marketplace::Serializers::DelistActionData.new(
            repository_action, current_user, request_url
          ).call
        }
      end

      private

      sig { returns(T.nilable(String)) }
      def readme_html
        Marketplace::Actions::GetReadmeHtml.new(
          repository_action: repository_action, selected_version: selected_version
        ).call
      end
    end
  end
end
