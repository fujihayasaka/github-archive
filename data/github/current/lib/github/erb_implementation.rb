# typed: true
# frozen_string_literal: true

require "action_view"
require "graphql/client/erubis_enhancer"
require "graphql/client/erubi_enhancer"

module GitHub
  class ErbImplementation < ActionView::Template::Handlers::ERB::Erubi
    prepend GraphQL::Client::ErubiEnhancer

    # test/rubocop/erb_parser.rb uses `ErbImplementation`, and `Rails` is not booted, so
    # `Rails.application` is not present at that time.
    if ENV["DISABLE_PRISM_FAST_RENDER_ENHANCER"]
      include GitHub::FastRenderEnhancer if (application = Rails.try(:application)) && application.config.cache_classes && !GitHub.admin_host?
    else
      include GitHub::PrismFastRenderEnhancer if (application = Rails.try(:application)) && application.config.cache_classes && !GitHub.admin_host?
    end
  end
end
