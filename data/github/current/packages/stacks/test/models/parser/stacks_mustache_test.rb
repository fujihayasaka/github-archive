# typed: true
# frozen_string_literal: true

require "test_helper"

class StacksMustacheTest < GitHub::TestCase
  fixtures do
    @if_block = "${{#If}} '${{{config.name}}}' ${{{config.name}}}${{/If}}"
    @config1 = JSON.parse('{"config" : { "name": "test" }}')
    @config2 = JSON.parse('{"config" : { "name_not_available": "na" }}')

    @is_not_array_block = "${{#IsNotArray}} '${{{config}}}' ${{{config.name}}}${{/IsNotArray}}"
    @is_array_block = "${{#IsNotArray}} '${{{config.inputs}}}' ${{{config.name}}}${{/IsNotArray}}"
    @config3 = JSON.parse('{"config" : { "name": "test", "inputs": ["test1", "test2"]}}')

    @yaml_step_block = "
    - name: CreateEnvironmentStep
      inputs:
        name: ${{{config.name}}}
        ${{#ExpandToYaml}}
        ${{{config.parameters}}}
        ${{/ExpandToYaml}}
    "
    @config4 = JSON.parse('{"config" : { "name": "test", "parameters": { "enforce-admins": true, "dismiss-stale-reviews": true, "require-code-owner-reviews" : true }}}')
    @yaml_step = JSON.parse('[{"name": "CreateEnvironmentStep", "inputs": {"name": "test", "enforce-admins": true, "dismiss-stale-reviews": true, "require-code-owner-reviews" : true }}]')
  end

  context "#render" do
    test "if helper tc" do
      assert_equal "test\n", StacksMustache.render(@if_block, @config1)
      assert_equal "\n", StacksMustache.render(@if_block, @config2)
    end

    test "IsNotArray helper tc" do
      assert_equal "test", StacksMustache.render(@is_not_array_block, @config1)
      assert_equal "", StacksMustache.render(@is_array_block, @config3)
    end

    test "ExpandToYaml helper tc" do
      assert_equal(@yaml_step, YAML.safe_load(StacksMustache.render(@yaml_step_block, @config4)))
    end

    test "If and IsNotArray combination tc" do
      step_string = YAML.safe_load(File.read(File.join(Rails.root, "packages/stacks/app/asset/stack_config_step_mapping.yaml")))["0.1.0"]["repo-metadata"]

      description = "nice description"

      topics = %w[
        topic1
        topic2
      ]

      description_config = StacksMustache.render(step_string, { "config" => { "parameters" => { "description" => description } } })
      description_config_expected = [{ "name" => "RepoMetadataStep", "inputs" => { "description" => description } }]
      assert_equal YAML.safe_load(description_config), description_config_expected

      topics_config = StacksMustache.render(step_string, { "config" => { "parameters" => { "topics" => topics } } })
      topics_config_expected = [{ "name" => "RepoMetadataStep", "inputs" => { "topics" => topics } }]
      assert_equal YAML.safe_load(topics_config), topics_config_expected

      description_topics_config = StacksMustache.render(step_string, { "config" => { "parameters" => { "topics" => topics,
        "description" => description } } })
      description_topics_config_expected = ["name" => "RepoMetadataStep", "inputs" => { "description" => description, "topics" => topics }]
      assert_equal YAML.safe_load(description_topics_config), description_topics_config_expected

      all_configs = StacksMustache.render(step_string, { "config" => { "parameters" => { "topics" => topics, "description" => description } } })
      all_configs_expected = [description_topics_config_expected[0]]
      assert_equal YAML.safe_load(all_configs), all_configs_expected
    end
  end

  context "tag change" do
    test "new tag works without affecting Mustache" do
      stack_mustache_template = "${{ input1 }} ${{{ input2 }}}"
      regular_mustache_template = "{{ input1 }} {{{ input2 }}}"
      inputs = { "input1": "working", "input2": "fine" }
      expected_output = "working fine"

      assert_equal StacksMustache.render(stack_mustache_template, inputs), expected_output
      assert_equal Mustache.render(regular_mustache_template, inputs), expected_output
    end
  end

  context "context miss" do
    test "raises error if key doesn't have value in inputs" do
      stack_mustache_template = "${{ input1 }} ${{{ input2 }}}"
      inputs  = { "input1": "working" }

      assert_raises Mustache::ContextMiss do
        StacksMustache.render(stack_mustache_template, inputs)
      end
    end
  end
end
