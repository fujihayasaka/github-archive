# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::PolicyVersionTest < GitHub::TestCase
  fixtures do
    @issue = create(:issue)
  end

  context ".version_for" do
    test "retrieves the pinned version for a subject-agnostic policy" do
      Permissions::PolicyVersion.stub_const(:SUBJECT_AGNOSTIC_POLICY_VERSIONS, { add_label: 2 }) do
        assert_equal 2, Permissions::PolicyVersion.version_for(action: :add_label)
      end
    end

    test "raises InvalidPolicyVersion for an array, because Callsites need to provide version" do
      Permissions::PolicyVersion.stub_const(:SUBJECT_AGNOSTIC_POLICY_VERSIONS, { add_label: 2, add_assignee: 2 }) do
        assert_raises(Permissions::PolicyVersion::InvalidPolicyVersion) do
          Permissions::PolicyVersion.version_for(action: [:add_label, :add_assignee])
        end
      end
    end

    test "raises InvalidPolicyVersion for an array of subject-agnostic policies if their versions do not match" do
      Permissions::PolicyVersion.stub_const(:SUBJECT_AGNOSTIC_POLICY_VERSIONS, { add_label: 2, add_assignee: 3 }) do
        assert_raises(Permissions::PolicyVersion::InvalidPolicyVersion) do
          Permissions::PolicyVersion.version_for(action: [:add_label, :add_assignee])
        end
      end
    end

    test "falls back to the sentinel value for a subject-agnostic policy that has not been pinned" do
      Permissions::PolicyVersion.stub_const(:SUBJECT_AGNOSTIC_POLICY_VERSIONS, {}) do
        assert_equal -1, Permissions::PolicyVersion.version_for(action: :add_label)
      end
    end

    test "retrieves the pinned version for a subject-specific policy" do
      Permissions::PolicyVersion.stub_const(:SUBJECT_AGNOSTIC_POLICY_VERSIONS, { add_label: 2 }) do
        Permissions::PolicyVersion.stub_const(:SUBJECT_SPECIFIC_POLICY_VERSIONS, { add_label: { issue: 3 } }) do
          assert_equal 3, Permissions::PolicyVersion.version_for(action: :add_label, subject: @issue)
        end
      end
    end

    test "falls back the subject-agnostic policy version for a subject-specific policy that has not been pinned as subject-specific" do
      Permissions::PolicyVersion.stub_const(:SUBJECT_AGNOSTIC_POLICY_VERSIONS, { add_label: 2 }) do
        Permissions::PolicyVersion.stub_const(:SUBJECT_SPECIFIC_POLICY_VERSIONS, {}) do
          assert_equal 2, Permissions::PolicyVersion.version_for(action: :add_label, subject: @issue)
        end
      end
    end

    test "falls back to the sentinel value for subject-specific policy that has not been pinned in any way" do
      Permissions::PolicyVersion.stub_const(:SUBJECT_AGNOSTIC_POLICY_VERSIONS, {}) do
        Permissions::PolicyVersion.stub_const(:SUBJECT_SPECIFIC_POLICY_VERSIONS, {}) do
          assert_equal -1, Permissions::PolicyVersion.version_for(action: :add_label, subject: @issue)
        end
      end
    end
  end
end
