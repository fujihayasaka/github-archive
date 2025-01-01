# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::FineGrainedResources::MetadataTest < GitHub::TestCase
  def subject
    Permissions::FineGrainedResources::Metadata
  end

  def apps_base_url
    Permissions::FineGrainedResources::Metadata::APPS_REST_PERMISSIONS_BASE_URL
  end

  def patsv2_base_url
    Permissions::FineGrainedResources::Metadata::PATSV2_REST_PERMISSIONS_BASE_URL
  end

  LOCALE = YAML.load_file(Rails.root.join("config/locales/programmatic_actor_fine_grained_resources.en.yml"))
  RESOURCE_META = LOCALE["en"]["programmatic_actor_fine_grained_resources"]
  ACTIONS_META = LOCALE["en"]["programmatic_actor_fine_grained_resource_actions"]

  context "i18n locale" do
    test "includes all subject types except for private", skip_enterprise: true do
      subject_types = (
        Repository::Resources.subject_types + \
        Organization::Resources.subject_types + \
        User::Resources.subject_types
      )

      subject_types -= Organization::Resources::PRIVATE_SUBJECT_TYPES
      flattened_subject_types = RESOURCE_META.keys

      missing_subjects = subject_types - flattened_subject_types
      assert_predicate missing_subjects.sort, :empty?
    end
  end

  context ".actions" do
    test "returns all actions as a hash" do
      # We store strings but I18n symbolizes them ¯\_(ツ)_/¯
      assert_equal ACTIONS_META.symbolize_keys, subject.actions
    end
  end

  context ".action_description" do
    test "none" do
      assert_equal "No access", subject.action_description(:none)
    end

    test "read" do
      assert_equal "Read-only", subject.action_description(:read)
    end

    test "write" do
      assert_equal "Read and write", subject.action_description(:write)
    end

    test "admin" do
      assert_equal "Admin", subject.action_description(:admin)
    end

    test "an undefined action uses 'none'" do
      assert_equal "No access", subject.action_description(:foo)
    end
  end

  context ".description" do
    test "returns a description if found from DESCRIPTIONS" do
      assert_equal RESOURCE_META["keys"]["description"], subject.description("keys")
    end

    test "returns an empty string if an description can't be found" do
      assert_nil RESOURCE_META["foo"]
      assert_empty subject.description("foo")
    end
  end

  context ".docs_url" do
    context "when there is no actor provided" do
      test "returns a URL with anchor provided in RESOURCE_DOCS_ANCHORS" do
        expected = apps_base_url + "#" + RESOURCE_META["administration"]["resource_group"] + "-permissions-for-" + RESOURCE_META["administration"]["title"].parameterize
        assert_equal expected, subject.docs_url("administration")
      end

      test "returns the REST docs if the resources is not in the list" do
        assert_equal apps_base_url, subject.docs_url("foo")
      end
    end

    context "when given an integration actor" do
      test "returns a URL with anchor provided in RESOURCE_DOCS_ANCHORS" do
        actor = build(:integration)
        expected = apps_base_url + "#" + RESOURCE_META["administration"]["resource_group"] + "-permissions-for-" + RESOURCE_META["administration"]["title"].parameterize
        assert_equal expected, subject.docs_url("administration", actor)
      end

      test "returns the REST docs if the resources is not in the list" do
        actor = build(:integration)
        assert_equal apps_base_url, subject.docs_url("foo", actor)
      end
    end

    context "when given a patv2 actor" do
      test "returns a URL with anchor provided in locale" do
        actor = build(:user_programmatic_access)
        expected = patsv2_base_url + "#" + RESOURCE_META["administration"]["resource_group"] + "-permissions-for-" + RESOURCE_META["administration"]["title"].parameterize
        assert_equal expected, subject.docs_url("administration", actor)
      end

      test "returns the REST docs if the resources is not in the list" do
        actor = build(:user_programmatic_access)
        assert_equal patsv2_base_url, subject.docs_url("foo", actor)
      end

      test "uses appropriate anchor for actor type" do
        actor = build(:user_programmatic_access)
        expected = patsv2_base_url + "#" + RESOURCE_META["blocking"]["resource_group"] + "-permissions-for-" + RESOURCE_META["blocking"]["title"].parameterize
        assert_equal expected, subject.docs_url("blocking", actor)
      end
    end
  end

  context ".title" do
    test "uses a title from locale if provided" do
      assert_equal RESOURCE_META["blocking"]["title"], subject.title("blocking")
    end

    test "humanizes resources not provided" do
      assert_equal "metadata".humanize, subject.title("metadata")
    end
  end
end
