# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::PlatformBaseTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    test "displays flash error when query invalid" do
      add_file_to_commands("graphql.yml", <<~YAML)
        ---
        trigger: graphql
        title: GraphQL
        steps:
        - type: graphql
          id: myQuery
          body: |-
            query {
              viewer {
                login1
              }
            }
      YAML

      command = build_user_defined_command("graphql", subject: @issue)
      command.process

      assert_equal command.flash.error, <<~MESSAGE.chomp
        Problem while executing step 1 (myQuery): {"errors"=>[{"path"=>["query", "viewer", "login1"], "extensions"=>{"code"=>"undefinedField", "typeName"=>"User", "fieldName"=>"login1"}, "locations"=>[{"line"=>3, "column"=>5}], "message"=>"Field 'login1' doesn't exist on type 'User'"}]}
      MESSAGE
    end
  end
end
