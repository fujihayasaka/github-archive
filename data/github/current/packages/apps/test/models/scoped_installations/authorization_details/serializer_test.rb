# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::SerializerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org  = create(:organization)

    @subject = ScopedInstallations::AuthorizationDetails::Serializer
  end

  context ".generate" do
    test "returns the hash and no error when successfully generated" do
      details, error_message = @subject.generate(
        permissions: { "metadata" => :read },
        repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Subset,
        repository_ids: [1]
      )

      assert_kind_of Hash, details
      assert_nil error_message
    end

    test "does not return the hash and responds with an error if there was an issue" do
      details, error_message = @subject.generate(
        permissions: { "metadata" => :read },
        repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Subset,
        repository_ids: (1..501).to_a
      )

      assert_nil details
      assert_equal "The property '#/subject_ids/repository' had more items than the allowed 500", error_message
    end
  end

  context ".validate" do
    context "version" do
      test "requires the version to be set" do
        valid, error_message = @subject.validate({})

        refute valid
        assert_equal "The property '#/' did not contain a required property of 'version'", error_message
      end

      test "requires the version to be set to 1" do
        valid, error_message = @subject.validate({ version: 2 })

        refute valid
        assert_equal "The property '#/version' value 2 did not match one of the following values: 1", error_message
      end
    end

    context "selections" do
      test "cannot be empty" do
        valid, error_message = @subject.validate({
          version: 1,
          selections: {}
        })

        refute valid
        assert_equal "The property '#/selections' did not contain a minimum number of properties 1", error_message
      end

      test "'repository' and 'organization' are the only valid selections" do
        valid, error_message = @subject.validate({
          version: 1,
          selections: {
            invalid_selection: "subset"
          }
        })

        refute valid

        expected_error_message = "The property '#/selections' contains additional properties [\"invalid_selection\"] outside of the schema when none are allowed"
        assert_equal expected_error_message, error_message
      end

      test "repository selection must be 'subset' or 'parent'" do
        valid, error_message = @subject.validate({
          version: 1,
          selections: {
            repository: "invalid"
          }
        })

        refute valid

        expected_error_message = "The property '#/selections/repository' value \"invalid\" did not match one of the following values: subset, parent, all"
        assert_equal expected_error_message, error_message
      end

      test "organization selection must be 'subset'" do
        valid, error_message = @subject.validate({
          version: 1,
          selections: {
            organization: "invalid"
          }
        })

        refute valid

        expected_error_message = "The property '#/selections/organization' value \"invalid\" did not match one of the following values: subset"
        assert_equal expected_error_message, error_message
      end

      test "codespace selection must be 'subset'" do
        valid, error_message = @subject.validate({
          version: 1,
          selections: {
            codespace: "invalid"
          }
        })

        refute valid

        expected_error_message = "The property '#/selections/codespace' value \"invalid\" did not match one of the following values: subset"
        assert_equal expected_error_message, error_message
      end
    end

    context "subject_ids" do
      test "cannot be empty" do
        valid, error_message = @subject.validate({
          version: 1,
          subject_ids: {}
        })

        refute valid
        assert_equal "The property '#/subject_ids' did not contain a minimum number of properties 1", error_message
      end

      context "repository" do
        test "requires at least one item" do
          valid, error_message = @subject.validate({
            version: 1,
            subject_ids: {
              repository: []
            }
          })

          refute valid
          assert_equal "The property '#/subject_ids/repository' did not contain a minimum number of items 1", error_message
        end

        test "requires all items to be integers" do
          valid, error_message = @subject.validate({
            version: 1,
            subject_ids: {
              repository: ["foo"]
            }
          })

          refute valid

          expected_error_message = "The property '#/subject_ids/repository/0' of type string did not match the following type: integer"
          assert_equal expected_error_message, error_message
        end

        test "limits the number of items to 500" do
          valid, error_message = @subject.validate({
            version: 1,
            subject_ids: {
              repository: (1..501).to_a
            }
          })

          refute valid
          assert_equal "The property '#/subject_ids/repository' had more items than the allowed 500", error_message
        end
      end

      context "organization" do
        test "limits the number of items to 1" do
          valid, error_message = @subject.validate({
            version: 1,
            subject_ids: {
              organization: [1, 2, 3]
            }
          })

          refute valid
          assert_equal "The property '#/subject_ids/organization' had more items than the allowed 1", error_message
        end

        test "requires all items to be an integer" do
          valid, error_message = @subject.validate({
            version: 1,
            subject_ids: {
              organization: ["foo"]
            }
          })

          refute valid

          expected_error_message = "The property '#/subject_ids/organization/0' of type string did not match the following type: integer"
          assert_equal expected_error_message, error_message
        end
      end
    end

    context "subject_types_and_actions" do
      test "cannot be empty" do
        valid, error_message = @subject.validate({
          version: 1,
          subject_types_and_actions: {}
        })

        refute valid
        assert_equal "The property '#/subject_types_and_actions' did not contain a minimum number of properties 1", error_message
      end

      test "does not accept invalid actions on permissions" do
        valid, error_message = @subject.validate({
          version: 1,
          subject_types_and_actions: {
            repository: { "metadata" => 5 }
          }
        })

        refute valid

        expected_error_message = "The property '#/subject_types_and_actions/repository/metadata' value 5 did not match one of the following values: 0, 1, 2"
        assert_equal expected_error_message, error_message
      end

      test "must be a valid object of resources and actions" do
        valid, error_message = @subject.validate({
          version: 1,
          subject_types_and_actions: {
            repository: [1, 2, 3]
          }
        })

        refute valid

        expected_error_message = "The property '#/subject_types_and_actions/repository' of type array did not match the following type: object"
        assert_equal expected_error_message, error_message
      end

      test "must only contain 'repository' or 'organization'" do
        valid, error_message = @subject.validate({
          version: 1,
          subject_types_and_actions: {
            foobar: { "metadata" => 0 }
          }
        })

        refute valid

        expected_error_message = "The property '#/subject_types_and_actions' contains additional properties [\"foobar\"] outside of the schema when none are allowed"
        assert_equal expected_error_message, error_message
      end
    end

    context "asymmetric" do
      test "cannot be empty" do
        valid, error_message = @subject.validate({
          version: 1,
          asymmetric: {}
        })

        refute valid
        assert_equal "The property '#/asymmetric' did not contain a minimum number of properties 1", error_message
      end

      test "does not accept invalid resource types" do
        valid, error_message = @subject.validate({
          version: 1,
          asymmetric: {
            "invalid" => { "metadata" => { "read" => [1] } }
          }
        })

        refute valid
        assert_equal "The property '#/asymmetric' contains additional properties [\"invalid\"] outside of the schema when none are allowed", error_message
      end

      test "does not accept invalid actions types" do
        valid, error_message = @subject.validate({
          version: 1,
          asymmetric: {
            "repository" => { "metadata" => { "invalid" => [1] } }
          }
        })

        refute valid
        assert_equal "The property '#/asymmetric/repository/metadata' contains additional properties [\"invalid\"] outside of the schema when none are allowed", error_message
      end

      test "requires at least resource per resource type" do
        valid, error_message = @subject.validate({
          version: 1,
          asymmetric: {
            "repository" => {}
          }
        })

        refute valid
        assert_equal "The property '#/asymmetric/repository' did not contain a minimum number of properties 1", error_message
      end

      test "requires at least action per resource per resource type" do
        valid, error_message = @subject.validate({
          version: 1,
          asymmetric: {
            "repository" => { "metadata" => {} }
          }
        })

        refute valid
        assert_equal "The property '#/asymmetric/repository/metadata' did not contain a minimum number of properties 1", error_message
      end

      test "requires at least subject ID per action per resource per resource type" do
        valid, error_message = @subject.validate({
          version: 1,
          asymmetric: {
            "repository" => { "metadata" => { "read" => [] } }
          }
        })

        refute valid
        assert_equal "The property '#/asymmetric/repository/metadata/read' did not contain a minimum number of items 1", error_message
      end
    end
  end

  context "#generate" do
    test "always adds the version" do
      details = @subject.new(
        target: nil,
        permissions: {},
        repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
        repository_ids: []
      ).generate

      assert_same_hash({ "version" => 1 }, details)
    end

    context "selections" do
      context "repository" do
        test "subset selection" do
          details = @subject.new(
            target: nil,
            permissions: { "metadata" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Subset,
            repository_ids: [1]
          ).generate

          assert_equal "subset", details["selections"]["repository"]
        end

        test "parent selection" do
          details = @subject.new(
            target: nil,
            permissions: { "metadata" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Parent,
            repository_ids: []
          ).generate

          assert_equal "parent", details["selections"]["repository"]
        end

        test "does not set a selection when repo permissions are not provided" do
          details = @subject.new(
            target: nil,
            permissions: {},
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Subset,
            repository_ids: []
          ).generate

          assert_same_hash({ "version" => 1 }, details)
        end
      end

      context "organization" do
        test "is set if the target is an org and there are relevant permissions" do
          details = @subject.new(
            target: @org,
            permissions: { "members" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_equal "subset", details["selections"]["organization"]
        end

        test "is not set if the target isn't an org but there are relevant permissions" do
          details = @subject.new(
            target: @user,
            permissions: { "members" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_nil details["selections"]
        end

        test "must have relevant permissions to be set when the target is an org" do
          details = @subject.new(
            target: @org,
            permissions: {},
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_nil details["selections"]
        end
      end
    end

    context "subject_ids" do
      context "repository" do
        test "sets the provided ids" do
          details = @subject.new(
            target: @org,
            permissions: { "metadata" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Subset,
            repository_ids: [1]
          ).generate

          assert_equal [1], details["subject_ids"]["repository"]
        end

        test "does not set the ids if the selection isn't subset" do
          details = @subject.new(
            target: @org,
            permissions: { "metadata" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Parent,
            repository_ids: [1]
          ).generate

          assert_nil details["subject_ids"]
        end

        test "does not set the ids if no repo permissions are provided" do
          details = @subject.new(
            target: @org,
            permissions: {},
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Subset,
            repository_ids: [1]
          ).generate

          assert_nil details["subject_ids"]
        end
      end

      context "organization" do
        test "sets the target as the id" do
          details = @subject.new(
            target: @org,
            permissions: { "members" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_equal [@org.id], details["subject_ids"]["organization"]
        end

        test "does not set the id if the target is not an org" do
          details = @subject.new(
            target: @user,
            permissions: { "members" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_nil details["subject_ids"]
        end

        test "does not set the id if there aren't any relevant permissions" do
          details = @subject.new(
            target: @org,
            permissions: {},
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_nil details["subject_ids"]
        end
      end
    end

    context "subject_types_and_actions" do
      context "repository" do
        test "sets permissions" do
          details = @subject.new(
            target: nil,
            permissions: { "metadata" => :read, "contents" => :write },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::Parent,
            repository_ids: []
          ).generate

          assert_same_hash({ "metadata" => 0, "contents" => 1 }, details["subject_types_and_actions"]["repository"])
        end

        test "does not set the permissions if the repository selection is 'none'" do
          details = @subject.new(
            target: nil,
            permissions: { "metadata" => :read, "contents" => :write },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_nil details["subject_types_and_actions"]
        end
      end

      context "organization" do
        test "sets permissions" do
          details = @subject.new(
            target: @org,
            permissions: { "members" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_same_hash({ "members" => 0 }, details["subject_types_and_actions"]["organization"])
        end

        test "does not set the permissions if the target is not an org" do
          details = @subject.new(
            target: @user,
            permissions: { "members" => :read },
            repository_selection: ::ScopedInstallations::AuthorizationDetails::Selection::None,
            repository_ids: []
          ).generate

          assert_nil details["subject_types_and_actions"]
        end
      end
    end
  end
end
