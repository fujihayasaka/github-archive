# typed: strict
# frozen_string_literal: true

module Marketplace
  module Actions
    class GetReadmeHtml
      include OcticonsHelper

      sig { returns(RepositoryAction) }
      attr_reader :repository_action

      sig { returns(T.nilable(String)) }
      attr_reader :selected_version

      sig { params(repository_action: RepositoryAction, selected_version: T.nilable(String)).void }
      def initialize(repository_action:, selected_version:)
        @repository_action = repository_action
        @selected_version = selected_version
      end

      delegate :repository, to: :repository_action, private: true

      sig { returns(T.nilable(String)) }
      def call
        committish = selected_version.presence || repository.default_branch
        readme = repository_action.readme(committish: committish)
        return unless readme
        context = {
          entity: repository,
          blob: readme,
          name: readme.path,
          anchor_icon: octicon("link"), # rubocop:disable Primer/PrimerOcticon
          path: File.dirname(readme.path),
          committish: committish,
        }

        GitHub::Goomba::MarkupPipeline.to_html(nil, context, cache_settings: { use_cache: true })
      end
    end
  end
end
