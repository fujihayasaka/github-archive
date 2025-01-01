# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::GraphQLTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    test "runs query and returns result" do
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
                login
              }
            }
      YAML
      command = build_user_defined_command("graphql", subject: @issue)

      command.process

      expected_result = { "data" => { "viewer" => { "login" => "monalisa" } } }
      assert_equal command.data["myQuery"], expected_result
    end

    test "injects variables into operations" do
      add_file_to_commands("retrieve_issue.yml", <<~YAML)
        ---
        trigger: retrieve_issue
        title: retrieve_issue
        steps:
        - type: graphql
          id: myQuery
          variables:
            id: "{{ command.resource.id }}"
          body: |-
            query RetrieveIssue($id: ID!) {
              node(id: $id) {
                ... on Issue {
                  number
                  author {
                    login
                  }
                }
              }
            }
      YAML

      command = build_user_defined_command("retrieve_issue", subject: @issue)

      command.process

      expected_result = {
        "data" => {
          "node" => {
            "number" => @issue.number,
            "author" => {
              "login" => @issue.user.login
            }
          }
        }
      }
      assert_equal command.data["myQuery"], expected_result
    end

    test "runs mutations" do
      add_file_to_commands("add_reaction.yml", <<~YAML)
        ---
        trigger: add_reaction
        title: add_reaction
        steps:
        - type: graphql
          id: reaction
          variables:
            subjectId: "{{ command.resource.id }}"
            content: HOORAY
          body: |-
            mutation AddReaction($subjectId: ID!, $content: ReactionContent!) {
              addReaction(input: { subjectId: $subjectId, content: $content }) {
                reaction {
                  content
                }
              }
            }
      YAML

      command = build_user_defined_command("add_reaction", subject: @issue)

      assert_difference -> { @issue.reactions.reload.count }, 1 do
        command.process
      end

      reaction = @issue.reactions.first
      assert_equal reaction.user, @owner
      assert_equal reaction.content, "tada"
    end
  end
end
