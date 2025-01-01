# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class WorkspaceEditor < Seeds::Runner
      REPOS_ORG = "repos-org"
      REPO_NAME = "maximum-effort"
      CONFIG_REPO_NAME = ".github"

      def self.help
        <<~HELP
        - Adds copilot_hadron_editor, Workspace Editor feature flags, corresponding feature preview.
        HELP
      end

      def self.run(options = {})
        require_relative "../../create-launch-github-app"

        user = Seeds::Objects::User.monalisa
        puts "--- Creating features ---"
        create_features(user)
      end

      def self.create_features(user)
        features = [
          :copilot_hadron_editor,
          :hadron_comment_fix_generation,
          :hadron_use_two_way_file_syncer,
          :hadron_force_access,
          :wrap_suggestion_html_in_hadron_panel,
        ]

        features.each do |feature_name|
          if !FlipperFeature.find_by(name: feature_name)
            FlipperFeature.create(name: feature_name).enable(user)
            puts "Created FlipperFeature: #{feature_name}"
          else
            puts "FlipperFeature: #{feature_name} already exists"
          end
        end

        copilot_hadron_editor_feature = FlipperFeature.find_by(name: :copilot_hadron_editor)

        if !Feature.find_by(slug: :copilot_hadron_editor)
          Feature.create(
            public_name: "New PR authorship experience",
            slug: :copilot_hadron_editor,
            flipper_feature: copilot_hadron_editor_feature,
            feedback_link: "https://github.com/community/community/discussions/categories/general-feedback",
            enrolled_by_default: true
          )
          puts "Created Feature: Workspace Editor"
        else
          puts "Feature: Workspace Editor already exists"
        end
      end
    end
  end
end
