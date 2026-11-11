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
          :file_uploading_in_workspace_editor,
          :hadron_comment_fix_generation,
          :hadron_force_access,
          :workspace_editor_fix_a_build_function_calling,
          :workspace_editor_pr_file_presence,
        ]

        features.each do |feature_name|
          Seeds::Objects::FeatureFlag.enable(feature_flag: feature_name, actor: user)
        end

        if !Feature.find_by(slug: :copilot_hadron_editor)
          Feature.create(
            public_name: "New PR authorship experience",
            slug: :copilot_hadron_editor,
            feature_flag_name: :copilot_hadron_editor,
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
