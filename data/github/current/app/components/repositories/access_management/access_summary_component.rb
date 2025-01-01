# typed: true
# frozen_string_literal: true

module Repositories
  module AccessManagement
    class AccessSummaryComponent < ApplicationComponent
      include EnterpriseManagedUsersHelper

      attr_reader :view

      def initialize(view:)
        @view = view
      end

      def repo_summary_icon
        case view.repo_visibility
        when "internal"
          "organization"
        when "private"
          "lock"
        when "public"
          "repo"
        end
      end
    end
  end
end
