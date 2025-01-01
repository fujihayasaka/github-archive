# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Memex
      def memex_automation_github_app_name
        "GitHub Project Automation"
      end

      def memex_automation_github_app_slug
        "github-project-automation"
      end
    end
  end

  extend Config::Memex
end
