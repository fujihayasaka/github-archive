# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsParsedWorkflowTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create :user, login: "monalisa"
    @repo = create :repository, owner: @owner, from_example: :simple

    @env_prod = create :environment, repository: @repo, name: "production"
    @env_dev = create :environment, repository: @repo, name: "dev"

    @commit_metadata = { committer: @repo.owner, message: "Updating a file" }

    ref = @repo.heads.find_or_build(@repo.default_branch)
    ref.append_commit(@commit_metadata, @repo.owner) do |files|
      files.add(".github/workflows/no-name.yml", <<~YAML
        on: [push]
        YAML
      )
      files.add(".github/workflows/quoted-name.yml", <<~YAML
        name: 'Workflow name'
        on: [push, workflow_dispatch]
        YAML
      )
      files.add(".github/workflows/on-workflow-dispatch.yml", <<~YAML
        on: workflow_dispatch
        YAML
      )
      files.add(".github/workflows/bom.yml", <<~YAML
        \uFEFFname: test
        on: workflow_dispatch
        YAML
      )
      files.add(".github/workflows/on-schedule.yml", <<~YAML
        on: schedule
        YAML
      )
      files.add(".github/workflows/on-array.yml", <<~YAML
        on: [workflow_dispatch, pull_request]
        YAML
      )
      files.add(".github/workflows/syntax-error.yml", <<~YAML
        on: [workflow_dispatch, pull_request
        YAML
      )
      files.add(".github/workflows/on-quoted.yml", <<~YAML
        'on': [push, workflow_dispatch]
        YAML
      )
      files.add(".github/workflows/multiple-triggers.yaml", <<~YAML
        name: Multiple triggers
        on:
          push:
            paths:
            - README.md
          workflow_dispatch:
        YAML
      )
      files.add(".github/workflows/on-wd-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          push:
            paths:
            - README.md
          workflow_dispatch:
            inputs:
              name:
                default: 'monalisa'
              numOctoCats:
                required: true
                description: 'Number of Octocats'
                default: '1'
        YAML
      )
      files.add(".github/workflows/required-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          push:
            paths:
            - README.md
          workflow_dispatch:
            inputs:
              name:
                default: 'monalisa'
              numOctoCats:
                required: true
                description: 'Number of Octocats'
              additional:
                default: 'suffix'
        YAML
      )
      files.add(".github/workflows/non-required-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          push:
            paths:
            - README.md
          workflow_dispatch:
            inputs:
              name:
              boolean:
                type: boolean
              choice:
                type: choice
              env:
                type: environment
        YAML
      )
      files.add(".github/workflows/non-required-inputs-defaults.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          push:
            paths:
            - README.md
          workflow_dispatch:
            inputs:
              name:
                default: 'default-name'
              boolean:
                type: boolean
              choice:
                type: choice
                default: 'default-choice'
                options: ['default-choice', 'other-choice']
              environment:
                type: environment
                default: 'dev'
        YAML
      )
      files.add(".github/workflows/choice-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              text:
              name:
                type: choice
                required: true
                default: cschleiden
                options:
                - monalisa
                - cschleiden
        YAML
      )
      files.add(".github/workflows/choice-inputs-none-options.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              name:
                type: choice
                required: true
        YAML
      )
      files.add(".github/workflows/boolean-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              disable:
                type: boolean
                default: true
              enable:
                type: boolean
                required: true
              false-default:
                type: boolean
                default: false
              not-required:
                type: boolean
                required: false
              false-default-not-required:
                type: boolean
                default: false
                required: false
              boolean-and-required-not-specified:
                type: boolean
        YAML
      )
      files.add(".github/workflows/number-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              default-one:
                type: number
                default: 1
              default-zero:
                type: number
                default: 0
              default-floating:
                type: number
                default: 12.3
              default-negative-floating:
                type: number
                default: -12.3
              default-scientific:
                type: number
                default: 1.23e+4
              default-hexa:
                type: number
                default: 0x123
              default-octa:
                type: number
                default: 0123
              required:
                type: number
                required: true
              not-required:
                type: number
                required: false
              negative-default-not-required:
                type: number
                default: -1
                required: false
              default-and-required-not-specified:
                type: number
        YAML
      )
      files.add(".github/workflows/invalid-number-inputs-default.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              one:
                type: number
                default: '1'
        YAML
      )
      files.add(".github/workflows/invalid-number-inputs-default2.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              one:
                type: number
                default: 'monalisa'
        YAML
      )
      files.add(".github/workflows/environment-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              required-env:
                type: environment
                required: true
              env:
                type: environment
                default: dev
        YAML
      )
      files.add(".github/workflows/choice-required-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              text:
              numOctoCats:
                type: choice
                required: true
                options:
                - 1
                - 2
        YAML
      )
      files.add(".github/workflows/invalid-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              name: ['test']
        YAML
      )
      files.add(".github/workflows/array-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs: ['name']
        YAML
      )
      files.add(".github/workflows/date-values.yaml", <<~YAML
        name: Date values
        on: [push]
        env:
          START_DATE: 2016-01-01
        YAML
      )
      files.add(".github/workflows/time-values.yaml", <<~YAML
        name: Time values
        on: [push]
        env:
          NYC_BALL_DROP: 2022-01-01T05:00:00Z
        YAML
      )
      files.add(".github/workflows/symbol-values.yaml", <<~YAML
      name: Symbol values
      on: [push]
      env:
        GRADLE_ARGUMENTS: :schema-loader:dockerfileLint
      YAML
    )
      files.add(".github/workflows/bad-input.yml", <<~YAML
        this is not valid yaml
        YAML
      )
      files.add(".github/workflows/callable-workflow.yaml", <<~YAML
        name: A Minimal Callable Workflow
        on:
          workflow_call:
        YAML
      )
      files.add(".github/workflows/empty-workflow.yml", "")
      files.add(".github/workflows/binary-file.yml", "\xff\x00\x2a")
      files.add(".github/workflows/folder.yml/hello-world.txt", "hello world")
      files.add(".github/workflows/workflow-with-actions.yaml", <<~YAML
        name: Workflow with actions
        on: [pull_request]
        jobs:
          test-job-1:
            runs-on: self-hosted
            steps:
            - name: run script
              run: |
                echo HELLO
            - name: using action 1
              uses: test-org/action1@v1
            - name: using action 2
              uses: test-org/action2@main
            - name: using action 3
              uses: test-org/action3@65234gsvdybdfxc4de
        YAML
      )
      files.add(".github/workflows/workflow-with-actions-and-called-workflows.yml", <<~YAML
        name: Workflow with actions and called workflows
        on: [pull_request]
        jobs:
          test-job-1:
            runs-on: self-hosted
            steps:
            - name: run script
              run: |
                echo HELLO
            - name: using action 1
              uses: test-org/action1@v1
            - name: using action 2
              uses: test-org/action2@main
            - name: using action 3
              uses: test-org/action3@65234gsvdybdfxc4de
          test-job-2:
            runs-on: self-hosted
            steps:
            - name: run script
              run: |
                echo HELLO
            - name: calling workflow 1
              uses: .github/workflows/reusable-wf-1.yml@main
            - name: using action 2
              uses: test-org/action2@main
            - uses: test-org/sample-repo/.github/workflows/reusable-wf-2.yml@65234gsvdybdfxc4de
        YAML
      )
    end

    @branch = @repo.heads.find_or_build("branch")
    @branch.append_commit(@commit_metadata, @repo.owner) do |files|
      files.add(".github/workflows/quoted-name.yml", <<~YAML
        name: 'Different name'
        on: [push, workflow_dispatch]
        YAML
      )
      files.add(".github/workflows/on-wd-inputs.yaml", <<~YAML
        name: Inputs for dispatch
        on:
          workflow_dispatch:
            inputs:
              name:
                default: 'monalisa'
                required: true
        YAML
      )
    end
  end

  context "file does not exist" do
    test "returns nil if file does not exist" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/does-not-exist.yml")

      assert_nil workflow
    end

    test "returns nil for empty path" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, "")

      assert_nil workflow
    end
  end

  context "invalid files" do
    test "returns nil for empty files" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/empty-file.yml")

      assert_nil workflow
    end

    test "returns nil for binary files" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/binary-file.yml")

      assert_nil workflow
    end

    test "returns nil for folders" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/folder.yml")

      assert_nil workflow
    end
  end

  context "#parse" do
    test "parses workflow with date values" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/date-values.yaml")

      refute_nil workflow
      assert_equal "Date values", workflow.name
      assert_equal ["push"], workflow.trigger_events
    end

    test "parses workflow with time values" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/time-values.yaml")

      refute_nil workflow
      assert_equal "Time values", workflow.name
      assert_equal ["push"], workflow.trigger_events
    end

    test "parses workflow with symbol values" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/symbol-values.yaml")

      refute_nil workflow
      assert_equal "Symbol values", workflow.name
      assert_equal ["push"], workflow.trigger_events
    end
  end

  context "#parse name" do
    test "parses name" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/multiple-triggers.yaml")

      refute_nil workflow
      assert_equal "Multiple triggers", workflow.name
    end

    test "parses quoted name" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/quoted-name.yml")

      refute_nil workflow
      assert_equal "Workflow name", workflow.name
    end

    test "falls back to path if no name given" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/no-name.yml")

      refute_nil workflow
      assert_equal ".github/workflows/no-name.yml", workflow.name
    end

    test "falls back to path with invalid input data" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/bad-input.yml")

      refute_nil workflow
      assert_equal ".github/workflows/bad-input.yml", workflow.name
    end
  end

  context "#parse from different branch" do
    test "parses quoted name from different branch" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/quoted-name.yml", @branch.qualified_name)

      refute_nil workflow
      assert_equal "Different name", workflow.name
    end
  end

  context "#parse triggers" do
    test "parses multiple trigger as object" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/multiple-triggers.yaml")

      refute_nil workflow
      assert workflow.has_workflow_dispatch_trigger?
    end

    test "parses trigger array" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/on-array.yml")

      refute_nil workflow
      assert workflow.has_workflow_dispatch_trigger?
    end

    test "parses single trigger with workflow_dispatch" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/on-workflow-dispatch.yml")

      refute_nil workflow
      assert workflow.has_workflow_dispatch_trigger?
    end

    test "parses trigger with bom" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/bom.yml")

      refute_nil workflow
      assert workflow.has_workflow_dispatch_trigger?
    end

    test "parses single trigger with schedule" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/on-schedule.yml")

      refute_nil workflow
      assert workflow.has_schedule_trigger?
    end

    test "parses trigger array when on is quoted" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/on-quoted.yml")

      refute_nil workflow
      assert workflow.has_workflow_dispatch_trigger?
    end

    test "does not have trigger with invalid input" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/bad-input.yml")

      refute_nil workflow
      refute workflow.has_workflow_dispatch_trigger?
    end

    test "parses trigger with on_call" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/callable-workflow.yaml")

      refute_nil workflow
      assert workflow.has_workflow_call_trigger?
    end

    test "parses no trigger when no on_call" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/array-inputs.yaml")

      refute_nil workflow
      refute workflow.has_workflow_call_trigger?
    end
  end

  context "#parse inputs" do
    test "nil when no workflow_dispatch event" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/no-name.yml")
      inputs = workflow.workflow_dispatch_inputs

      assert_nil inputs
    end

    test "nil when no inputs defined" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/on-array.yml")
      inputs = workflow.workflow_dispatch_inputs

      assert_nil inputs
    end

    test "nil when file has syntax errors" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/syntax-error.yml")
      inputs = workflow.workflow_dispatch_inputs

      assert_nil inputs
    end

    test "nil when inputs are incorrectly defined as array" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/array-inputs.yaml")
      inputs = workflow.workflow_dispatch_inputs

      assert_nil inputs
    end

    test "nil when an input is not in the correct format" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/invalid-inputs.yaml")
      inputs = workflow.workflow_dispatch_inputs

      assert_nil inputs
    end

    test "parses inputs successfully" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/on-wd-inputs.yaml")
      inputs = workflow.workflow_dispatch_inputs

      refute_nil inputs

      assert_equal ({
        "name" => {
          description: "",
          required: false,
          default: "monalisa",
          type: "text",
        },
        "numOctoCats" => {
          description: "Number of Octocats",
          required: true,
          default: "1",
          type: "text",
        },
      }), inputs
    end

    context "#typed inputs" do
      test "parses typed inputs successfully" do
        workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/choice-inputs.yaml", nil)
        inputs = workflow.workflow_dispatch_inputs

        refute_nil inputs

        assert_equal ({
          "text" => {
            description: "",
            required: false,
            default: "",
            type: "text",
          },
          "name" => {
            description: "",
            required: true,
            default: "cschleiden",
            type: "choice",
            options: %w[monalisa cschleiden]
          },
        }), inputs
      end

      test "parses choice inputs successfully when options are none" do
        workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/choice-inputs-none-options.yaml", nil)
        inputs = workflow.workflow_dispatch_inputs

        refute_nil inputs

        assert_equal ({
          "name" => {
            description: "",
            required: true,
            default: "",
            type: "choice",
            options: []
          },
        }), inputs
      end
    end

    test "parses inputs successfully from non-default branch" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/on-wd-inputs.yaml", @branch.qualified_name)
      inputs = workflow.workflow_dispatch_inputs

      refute_nil inputs

      assert_equal ({
        "name" => {
          description: "",
          required: true,
          default: "monalisa",
          type: "text",
        }
      }), inputs
    end

    test "parses inputs succesfully when events use object notation" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/multiple-triggers.yaml")
      inputs = workflow.workflow_dispatch_inputs

      assert_nil inputs
    end
  end

  context "#process_inputs" do
    test "raises error when missing required inputs" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/required-inputs.yaml")

      error = assert_raises ArgumentError do
        workflow.process_inputs({
          "name" => "monalisa",
        })
      end

      assert_equal "Required input 'numOctoCats' not provided", error.message
    end

    test "raises error for unexpected inputs" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/on-wd-inputs.yaml")

      error = assert_raises ArgumentError do
        workflow.process_inputs({
          "not_known" => "value"
        })
      end

      assert_equal "Unexpected inputs provided: [\"not_known\"]", error.message
    end

    context "#typed inputs" do
      context "#choice" do
        test "raises error when given value not in list of options" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/choice-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "name" => "extra_value"
            })
          end

          assert_equal "Provided value 'extra_value' for input 'name' not in the list of allowed values", error.message
        end

        test "raises error when no value given for required choice input" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/choice-required-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({})
          end

          assert_equal "Required input 'numOctoCats' not provided", error.message
        end

        test "process to be nil or defaults for non-required inputs with no defaults" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/non-required-inputs.yaml", nil)

          inputs = workflow.process_inputs({})

          assert_nil inputs["name"]
          assert_equal "false", inputs["boolean"]
          assert_nil inputs["choice"]
          assert_nil inputs["environment"]
        end

        test "process to be defaults for non-required inputs with defaults" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/non-required-inputs-defaults.yaml", nil)

          inputs = workflow.process_inputs({})

          assert_equal "default-name", inputs["name"]
          assert_equal "false", inputs["boolean"]
          assert_equal "default-choice", inputs["choice"]
          assert_equal "dev", inputs["environment"]
        end

        test "forces options to be strings" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/choice-required-inputs.yaml", nil)

          inputs = workflow.process_inputs({
            "numOctoCats" => "2"
          })

          assert_equal "2", inputs["numOctoCats"]
        end

        test "processes choice input" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/choice-inputs.yaml", nil)

          inputs = workflow.process_inputs({
            "name" => "monalisa"
          })

          assert_equal "monalisa", inputs["name"]
        end

        test "processes choice input with default value" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/choice-inputs.yaml", nil)

          inputs = workflow.process_inputs({
            "name" => ""
          })

          assert_equal "cschleiden", inputs["name"]
        end
      end

      context "#boolean" do
        test "processes boolean inputs" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/boolean-inputs.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({
              "disable" => "false",
              "enable" => "true",
              "false-default" => "true",
              "not-required" => "false",
              "false-default-not-required" => "true",
              "boolean-and-required-not-specified" => "false",
            })
          end

          assert_equal "false", inputs["disable"]
          assert_equal "true", inputs["enable"]
          assert_equal "true", inputs["false-default"]
          assert_equal "false", inputs["not-required"]
          assert_equal "true", inputs["false-default-not-required"]
          assert_equal "false", inputs["boolean-and-required-not-specified"]
        end

        test "processes boolean inputs with default values" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/boolean-inputs.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({
              "enable" => "true",
            })
          end

          assert_equal "true", inputs["disable"]
          assert_equal "true", inputs["enable"]
          assert_equal "false", inputs["false-default"]
          assert_equal "false", inputs["not-required"]
          assert_equal "false", inputs["false-default-not-required"]
          assert_equal "false", inputs["boolean-and-required-not-specified"]
        end

        test "raises error when required boolean input not set" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/boolean-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "disable" => "true",
            })
          end

          assert_equal "Required input 'enable' not provided", error.message
        end

        test "allow empty string for boolean inputs" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/boolean-inputs.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({
              "boolean-and-required-not-specified" => "",
              "enable" => "true",
            })
          end

          assert_equal "true", inputs["disable"]
          assert_equal "true", inputs["enable"]
          assert_equal "false", inputs["false-default"]
          assert_equal "false", inputs["not-required"]
          assert_equal "false", inputs["false-default-not-required"]
          assert_equal "false", inputs["boolean-and-required-not-specified"]
        end

        test "allow literal for boolean inputs" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/boolean-inputs.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({
              "boolean-and-required-not-specified" => "",
              "enable" => false,
              "false-default" => true,
            })
          end

          assert_equal "true", inputs["disable"]
          assert_equal "false", inputs["enable"]
          assert_equal "true", inputs["false-default"]
          assert_equal "false", inputs["not-required"]
          assert_equal "false", inputs["false-default-not-required"]
          assert_equal "false", inputs["boolean-and-required-not-specified"]
        end

        test "only allows true/false, empty string for boolean inputs" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/boolean-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "disable" => "123",
              "enable" => "true",
            })
          end

          assert_equal "Provided value '123' for input 'disable' not in the list of allowed values", error.message
        end
      end

      context "#environment" do
        test "processes environment inputs" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/environment-inputs.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({
              "required-env" => @env_prod.name,
              "env" => @env_dev.name,
            })
          end

          assert_equal @env_prod.name, inputs["required-env"]
          assert_equal @env_dev.name, inputs["env"]
        end

        test "processes environment inputs with default values" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/environment-inputs.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({
              "required-env" => @env_prod.name,
            })
          end

          assert_equal @env_prod.name, inputs["required-env"]
          assert_equal "dev", inputs["env"]
        end

        test "raises error when required environment input not set" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/environment-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "env" => @env_dev.name,
            })
          end

          assert_equal "Required input 'required-env' not provided", error.message
        end

        test "only allows environment names for environment inputs" do
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/environment-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "required-env" => "does-not-exist"
            })
          end

          assert_equal "Provided environment 'does-not-exist' does not exist in the repository", error.message
        end
      end

      context "#number" do
        test "processes number inputs" do
          GitHub.flipper[:actions_number_type_dispatch_inputs].enable
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/number-inputs.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({
              "default-one" => 0,
              "default-zero" => 1,
              "default-floating" => 1.2,
              "default-negative-floating" => -1.2,
              "default-scientific" => 1.23e+4,
              "default-hexa" => 0x12,
              "default-octa" => 011,
              "required" => 2,
              "not-required" => 3,
              "negative-default-not-required" => 4,
              "default-and-required-not-specified" => 5,
            })
          end

          assert_equal 0, inputs["default-one"]
          assert_equal 1, inputs["default-zero"]
          assert_equal 1.2, inputs["default-floating"]
          assert_equal -1.2, inputs["default-negative-floating"]
          assert_equal 12300, inputs["default-scientific"]
          assert_equal 18, inputs["default-hexa"]
          assert_equal 9, inputs["default-octa"]
          assert_equal 2, inputs["required"]
          assert_equal 3, inputs["not-required"]
          assert_equal 4, inputs["negative-default-not-required"]
          assert_equal 5, inputs["default-and-required-not-specified"]
        end

        test "processes number inputs with default values" do
          GitHub.flipper[:actions_number_type_dispatch_inputs].enable
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/number-inputs.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({
              "required" => 2,
            })
          end

          assert_equal 1, inputs["default-one"]
          assert_equal 0, inputs["default-zero"]
          assert_equal 12.3, inputs["default-floating"]
          assert_equal -12.3, inputs["default-negative-floating"]
          assert_equal 12300, inputs["default-scientific"]
          assert_equal 291, inputs["default-hexa"]
          assert_equal 83, inputs["default-octa"]
          assert_equal 2, inputs["required"]
          assert_equal 0, inputs["not-required"]
          assert_equal -1, inputs["negative-default-not-required"]
          assert_equal 0, inputs["default-and-required-not-specified"]
        end

        test "raises error when required number input not set" do
          GitHub.flipper[:actions_number_type_dispatch_inputs].enable
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/number-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "default-one" => 2,
            })
          end

          assert_equal "Required input 'required' not provided", error.message
        end

        test "raises error when empty string is given for number inputs" do
          GitHub.flipper[:actions_number_type_dispatch_inputs].enable
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/number-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "required" => 2,
              "not-required" => "",
              "default-and-required-not-specified" => 3,
            })
          end

          assert_equal "Provided value '' for input 'not-required' is not a number", error.message
        end

        test "raises error when input is not a number" do
          GitHub.flipper[:actions_number_type_dispatch_inputs].enable
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/number-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "default-one" => "abc12",
            })
          end

          assert_equal "Provided value 'abc12' for input 'default-one' is not a number", error.message
        end

        test "raises error when feature flag is disabled" do
          GitHub.flipper[:actions_number_type_dispatch_inputs].disable
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/number-inputs.yaml", nil)

          error = assert_raises ArgumentError do
            workflow.process_inputs({
              "default-one" => 1,
            })
          end

          assert_equal "Invalid value for input 'default-one'", error.message
        end

        test "set default value as 0 when input is quoted number" do
          GitHub.flipper[:actions_number_type_dispatch_inputs].enable
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/invalid-number-inputs-default.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({})
          end

          assert_equal 0, inputs["one"]
        end

        test "set default value as 0 when default value is not a number" do
          GitHub.flipper[:actions_number_type_dispatch_inputs].enable
          workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/invalid-number-inputs-default2.yaml", nil)

          inputs = assert_nothing_raised do
            workflow.process_inputs({})
          end

          assert_equal 0, inputs["one"]
        end
      end
    end
  end

  context "#referenced-actions" do
    test "returns expected actions after parsing a valid workflow" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/workflow-with-actions.yaml")

      actions = workflow.referenced_actions
      assert_equal 3, actions.count
      assert actions.include?("test-org/action3@65234gsvdybdfxc4de")
    end

    test "returns expected actions and workflows after parsing a valid workflow" do
      workflow = Actions::ParsedWorkflow.parse_from_yaml(@repo, ".github/workflows/workflow-with-actions-and-called-workflows.yml")

      actions = workflow.referenced_actions
      assert_equal 6, actions.count
      assert actions.include?("test-org/sample-repo/.github/workflows/reusable-wf-2.yml@65234gsvdybdfxc4de")
    end
  end
end
