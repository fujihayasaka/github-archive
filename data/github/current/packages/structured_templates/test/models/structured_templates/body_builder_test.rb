# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplates::BodyBuilderTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    raw_data = <<~YAML
      ---
      name: Cat Report
      body:
      - type: textarea
        attributes:
          label: "Favorite cat?"
          description: "Tell us about your favorite cat and why"
      - type: textarea
        attributes:
          label: "Favorite dog?!?"
          description: "Tell us about your favorite dog and why"
      - type: dropdown
        attributes:
          label: "Favorite reptile?"
          description: "Choose your favorite reptile"
          options:
            - Snek
            - Snake
      - type: dropdown
        attributes:
          label: "Favorite horses?"
          description: "Choose all your favorite horses"
          multiple: true
          options:
            - Mr Ed
            - Black Beauty
            - Seabiscuit
    YAML

    discussion_raw_data = <<~YAML
      ---
      body:
      - type: markdown
        attributes:
          value: "Welcome to our template"
      - type: textarea
        attributes:
          label: "Favorite cat?"
          description: "Tell us about your favorite cat and why"
      - type: textarea
        attributes:
          label: "Favorite dog?!?"
          description: "Tell us about your favorite dog and why"
    YAML

    config = IssueForms::TemplateConfig.new(input: raw_data, path: "some/path").load
    filename = ".github/ISSUE_TEMPLATE/bug.yaml"
    @repo = create(:repository)
    @template = IssueTemplate.new_from_structured_template_config(config: config, repository: @repo, filename: filename)

    discussion_config = DiscussionForms::TemplateConfig.new(input: discussion_raw_data, path: "some/path").load
    @discussion_template = DiscussionTemplate.new(
      repository: @repo,
      config: discussion_config,
      filename: ".github/DISCUSSION_TEMPLATE/general.yml",
    )
  end

  test "renders a structured label in bold in the configured order, with user's input after a linebreak" do
    params = {
      "#{Digest::SHA256.hexdigest("Favorite cat?")}" => "Samsicle, because he is an orange murder floof",
      "#{Digest::SHA256.hexdigest("Favorite dog?!?")}" => "Lola, for showing the chewy ball who's boss",
      "#{Digest::SHA256.hexdigest("Favorite reptile?")}" => "Snek",
      "#{Digest::SHA256.hexdigest("Favorite horses?")}" => ["Mr Ed", "Seabiscuit"]
    }

    expected = <<~TXT.chomp
      ### Favorite cat?

      Samsicle, because he is an orange murder floof

      ### Favorite dog?!?

      Lola, for showing the chewy ball who's boss

      ### Favorite reptile?

      Snek

      ### Favorite horses?

      Mr Ed, Seabiscuit
    TXT

    builder = StructuredTemplates::BodyBuilder.new(form_params: params, template: @template)
    assert_equal expected, builder.to_markdown
  end

  test "ignores extra response params not in the template config" do
    params = {
      "#{Digest::SHA256.hexdigest("Favorite cat?")}" => "Samsicle",
      "#{Digest::SHA256.hexdigest("Favorite dog?!?")}" => "Lola",
      "favorite_plant" => "Piranha",
    }

    expected = <<~TXT.chomp
      ### Favorite cat?

      Samsicle

      ### Favorite dog?!?

      Lola

      ### Favorite reptile?

      _No response_

      ### Favorite horses?

      _No response_
    TXT

    builder = StructuredTemplates::BodyBuilder.new(form_params: params, template: @template)
    assert_equal expected, builder.to_markdown
  end

  test "renders question with blank response placeholder for unanswered and blank-string fields" do
    params = {
      "#{Digest::SHA256.hexdigest("Favorite cat?")}" => "",
    }

    expected = <<~TXT.chomp
      ### Favorite cat?

      _No response_

      ### Favorite dog?!?

      _No response_

      ### Favorite reptile?

      _No response_

      ### Favorite horses?

      _No response_
    TXT

    builder = StructuredTemplates::BodyBuilder.new(form_params: params, template: @template)
    assert_equal expected, builder.to_markdown
  end

  test "does not include markdown input type in generated markdown" do
    data = <<~YAML
      name: Paddington Bear
      body:
      - type: markdown
        attributes:
          value: "Paddington Bear is so kind and lovely, prove me wrong"
      - type: textarea
        attributes:
          label: "Favorite Paddington moment?"
    YAML

    config = IssueForms::TemplateConfig.new(input: data, path: nil).load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: ".github/ISSUE_TEMPLATE/paddington.yaml",
    )

    params = {
      "#{Digest::SHA256.hexdigest("Favorite Paddington moment?")}" => "eating marmalade",
    }

    expected = <<~TXT.chomp
      ### Favorite Paddington moment?

      eating marmalade
    TXT

    builder = StructuredTemplates::BodyBuilder.new(
      form_params: params,
      template: template,
    )
    assert_equal expected, builder.to_markdown
  end

  test "does not include issue body, that is not a thing anymore" do
    data = <<~YAML
      name: Paddington Bear
      body:
      - type: textarea
        attributes:
          label: "Favorite Paddington moment?"
    YAML

    config = IssueForms::TemplateConfig.new(input: data, path: nil).load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: ".github/ISSUE_TEMPLATE/paddington.yaml",
    )

    params = {
      "#{Digest::SHA256.hexdigest("Favorite Paddington moment?")}" => "eating marmalade",
    }

    expected = <<~TXT.chomp
      ### Favorite Paddington moment?

      eating marmalade
    TXT

    builder = StructuredTemplates::BodyBuilder.new(
      form_params: params,
      template: template,
    )
    assert_equal expected, builder.to_markdown
  end

  test "works with checkboxes" do
    data = <<~YAML
      name: Paddington Bear
      body:
      - type: checkboxes
        attributes:
          label: "Favorite bear foods?"
          options:
            - label: Honey
            - label: Marmalade
              required: true
            - label: Other
    YAML

    params = {
      "#{Digest::SHA256.hexdigest("Favorite bear foods?")}" => {
        "#{Digest::SHA256.hexdigest("Marmalade")}" => "marmalade",
        "#{Digest::SHA256.hexdigest("Other")}" => "other"
      }
    }

    config = IssueForms::TemplateConfig.new(input: data, path: nil).load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: ".github/ISSUE_TEMPLATE/paddington.yaml",
    )

    builder = StructuredTemplates::BodyBuilder.new(
      form_params: params,
      template: template,
    )

    expected = <<~TXT.chomp
      ### Favorite bear foods?

      - [ ] Honey
      - [X] Marmalade
      - [X] Other
    TXT

    assert_equal expected, builder.to_markdown
  end

  test "will add codeblock if render is passed in the form" do
    data = <<~YAML
      name: Bug report
      body:
      - type: textarea
        attributes:
          label: "Include code sample"
          render: ruby
    YAML

    config = IssueForms::TemplateConfig.new(input: data, path: nil).load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: ".github/ISSUE_TEMPLATE/bug_report.yaml",
    )

    params = {
      "#{Digest::SHA256.hexdigest("Include code sample")}" => "def foo\n\sputs 'bar'\nend",
    }

    expected = <<~TXT.chomp
      ### Include code sample

      ```ruby
      def foo
       puts 'bar'
      end
      ```

    TXT

    builder = StructuredTemplates::BodyBuilder.new(
      form_params: params,
      template: template,
    )
    assert_equal expected, builder.to_markdown
  end

  test "will still render correctly if user passes in backticks with a language" do
    data = <<~YAML
      name: Bug report
      body:
      - type: textarea
        attributes:
          label: "Include code sample"
          render: ruby
    YAML

    config = IssueForms::TemplateConfig.new(input: data, path: nil).load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: ".github/ISSUE_TEMPLATE/bug_report.yaml",
    )

    params = {
      "#{Digest::SHA256.hexdigest("Include code sample")}" => "```shell\ndef foo\n\sputs 'bar'\nend\n```",
    }

    expected = <<~TXT.chomp
      ### Include code sample

      ```ruby
      def foo
       puts 'bar'
      end
      ```

    TXT

    builder = StructuredTemplates::BodyBuilder.new(
      form_params: params,
      template: template,
    )
    assert_equal expected, builder.to_markdown
  end

  test "will render correctly even if backticks are passed in" do
    data = <<~YAML
      name: Bug report
      body:
      - type: textarea
        attributes:
          label: "Include code sample"
          render: ruby
    YAML

    config = IssueForms::TemplateConfig.new(input: data, path: nil).load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: ".github/ISSUE_TEMPLATE/bug_report.yaml",
    )

    params = {
      "#{Digest::SHA256.hexdigest("Include code sample")}" => "```\ndef foo\n\sputs 'bar'\nend",
    }

    expected = <<~TXT.chomp
      ### Include code sample

      ```ruby
      def foo
       puts 'bar'
      end
      ```

    TXT

    builder = StructuredTemplates::BodyBuilder.new(
      form_params: params,
      template: template,
    )
    assert_equal expected, builder.to_markdown
  end

  test "does not render a codeblock if no answer is passed" do
    data = <<~YAML
      name: Bug report
      body:
      - type: textarea
        attributes:
          label: "Include code sample"
          render: ruby
    YAML

    config = IssueForms::TemplateConfig.new(input: data, path: nil).load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: ".github/ISSUE_TEMPLATE/bug_report.yaml",
    )

    params = {
      "#{Digest::SHA256.hexdigest("Include code sample")}" => "",
    }

    builder = StructuredTemplates::BodyBuilder.new(
      form_params: params,
      template: template,
    )

    expected = <<~TXT.chomp
      ### Include code sample

      _No response_
    TXT

    assert_equal expected, builder.to_markdown
  end

  test "ignores value of textarea_helper_element because that is the fake WYSIWYG helper that will contain duplicate responses" do
    data = <<~YAML
      name: Bug report
      body:
      - type: textarea
        attributes:
          label: What happened
    YAML

    config = IssueForms::TemplateConfig.new(input: data, path: nil).load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: ".github/ISSUE_TEMPLATE/bug_report.yaml",
    )

    params = {
      "#{Digest::SHA256.hexdigest("What happened")}" => "sneak attack",
      "textarea_helper_element" => "sneak attack 2",
    }

    builder = StructuredTemplates::BodyBuilder.new(
      form_params: params,
      template: template,
      )

    expected = <<~TXT.chomp
      ### What happened

      sneak attack
    TXT

    assert_equal expected, builder.to_markdown
  end

  test "renders body for discussion template" do
    params = {
      "#{Digest::SHA256.hexdigest("Favorite cat?")}" => "Samsicle, because he is an orange murder floof",
      "#{Digest::SHA256.hexdigest("Favorite dog?!?")}" => "Lola, for showing the chewy ball who's boss",
    }

    expected = <<~TXT.chomp
      ### Favorite cat?

      Samsicle, because he is an orange murder floof

      ### Favorite dog?!?

      Lola, for showing the chewy ball who's boss
    TXT

    builder = StructuredTemplates::BodyBuilder.new(form_params: params, template: @discussion_template)
    assert_equal expected, builder.to_markdown
  end
end
