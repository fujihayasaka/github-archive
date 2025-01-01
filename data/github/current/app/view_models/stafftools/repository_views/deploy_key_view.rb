# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class DeployKeyView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :repository

      def page_title
        "#{repository.name_with_owner} - Deploy Keys"
      end

      def deploy_keys?
        deploy_keys.any?
      end

      def deploy_keys
        repository.public_keys
      end

    end
  end
end
