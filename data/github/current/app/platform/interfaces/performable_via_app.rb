# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module PerformableViaApp
      include Platform::Interfaces::Base
      description "Represents items that can be created or performed via GitHub Apps."
      visibility :internal

      field :via_app, Objects::App, description: "The GitHub App that created this object.", visibility: :internal, null: true

      def via_app
        @object.async_performed_via_integration.then do |app|
          next unless app

          app.async_readable_by?(@context[:viewer]).then do |is_viewable|
            app if is_viewable
          end
        end
      end
    end
  end
end
