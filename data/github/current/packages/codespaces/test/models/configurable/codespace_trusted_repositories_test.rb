# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespaceTrustedRepositoriesTest < GitHub::TestCase
  entity_types = [:organization, :user]

  fixtures do
    @setting_user = create(:user)

    entity_types.each do |type|
      instance_variable_set("@#{type}", create(type))
    end
  end

  context "#update_codespace_trusted_repositories_access" do
    test "audits codespace_trusted_repositories_access" do
      assert_includes Audit::ACTIONS, "codespaces.trusted_repositories_access_update"
    end

    entity_types.each do |type|
      test "sets codespace extended repo access to all for #{type}" do
        entity = instance_variable_get("@#{type}")
        assert_equal Configurable::CodespaceTrustedRepositories::DISABLED, entity.codespace_trusted_repositories_access
        entity.update_codespace_trusted_repositories_access(Configurable::CodespaceTrustedRepositories::ALL_REPOS, actor: @setting_user)
        assert_equal Configurable::CodespaceTrustedRepositories::ALL_REPOS, entity.codespace_trusted_repositories_access
      end

      test "sets codespace extended repo access to selected for #{type}" do
        entity = instance_variable_get("@#{type}")
        assert_equal Configurable::CodespaceTrustedRepositories::DISABLED, entity.codespace_trusted_repositories_access
        entity.update_codespace_trusted_repositories_access(Configurable::CodespaceTrustedRepositories::SELECTED_REPOS, actor: @setting_user)
        assert_equal Configurable::CodespaceTrustedRepositories::SELECTED_REPOS, entity.codespace_trusted_repositories_access
      end

      test "sets codespace extended repo access to none for #{type}" do
        entity = instance_variable_get("@#{type}")
        assert_equal Configurable::CodespaceTrustedRepositories::DISABLED, entity.codespace_trusted_repositories_access
        entity.update_codespace_trusted_repositories_access(Configurable::CodespaceTrustedRepositories::DISABLED, actor: @setting_user)
        assert_equal Configurable::CodespaceTrustedRepositories::DISABLED, entity.codespace_trusted_repositories_access
      end

      test "raises error when given invalid access type for #{type}" do
        entity = instance_variable_get("@#{type}")
        assert_equal Configurable::CodespaceTrustedRepositories::DISABLED, entity.codespace_trusted_repositories_access
        assert_raises Configurable::CodespaceTrustedRepositories::InvalidRepoAccessArgumentError do
          entity.update_codespace_trusted_repositories_access("a different string", actor: @setting_user)
        end
        assert_equal Configurable::CodespaceTrustedRepositories::DISABLED, entity.codespace_trusted_repositories_access
      end

      test "instruments codespace_trusted_repositories_access for #{type}" do
        prefix = get_event_prefix(type)
        entity = instance_variable_get("@#{type}")
        events = subscribe "codespaces.trusted_repositories_access_update"
        entity.update_codespace_trusted_repositories_access(Configurable::CodespaceTrustedRepositories::DISABLED, actor: @setting_user)
        assert event = events.pop, "an codespaces.trusted_repositories_access_update event was expected"
        assert_equal "codespaces.trusted_repositories_access_update", event.name
        assert_equal event.payload[:"#{prefix}_id"], entity.id
      end
    end
  end

  private

  def get_event_prefix(type)
    {
      organization: :org,
      user: :user,
    }[type]
  end
end unless GitHub.enterprise?
