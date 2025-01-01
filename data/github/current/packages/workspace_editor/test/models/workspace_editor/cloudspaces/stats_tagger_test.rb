# typed: true
# frozen_string_literal: true

require "test_helper"

module WorkspaceEditor::Cloudspaces
  class StatsTaggerTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @cloud_environment = create(:cloud_environment)
    end

    test "adds is_workspace_editor_cloud_environment:true", skip_enterprise: true do
      all_tags = WorkspaceEditor::Cloudspaces::StatsTagger.new(codespace: @cloud_environment).all_tags
      assert all_tags[:is_workspace_editor_cloud_environment]
    end
  end
end
