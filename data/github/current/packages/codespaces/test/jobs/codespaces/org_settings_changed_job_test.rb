# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgSettingsChangedJobTest < GitHub::TestCase
  test "calls GlobalInstrumenter for disabling organization" do
    GlobalInstrumenter.expects(:instrument).
      once.with(::Codespaces::Events::ORG_CODESPACES_DISABLED, { organization_id: 1, actor_id: 1 })

    Codespaces::OrgSettingsChangedJob.perform_now(context: 1, event_type: ::Codespaces::Events::ORG_CODESPACES_DISABLED, actor_id: 1)
  end

  test "calls GlobalInstrumenter for enabling organization" do
    GlobalInstrumenter.expects(:instrument).
      once.with(::Codespaces::Events::ORG_CODESPACES_ENABLED, { organization_id: 1, actor_id: 1 })

    Codespaces::OrgSettingsChangedJob.perform_now(context: 1, event_type: ::Codespaces::Events::ORG_CODESPACES_ENABLED, actor_id: 1)
  end

  test "calls GlobalInstrumenter for disabling organization - ignoring billing owner" do
    GlobalInstrumenter.expects(:instrument).
      once.with(::Codespaces::Events::ORG_REPO_OWNED_CODESPACES_DISABLED, { organization_id: 1, actor_id: 1 })

    Codespaces::OrgSettingsChangedJob.perform_now(context: 1, event_type: ::Codespaces::Events::ORG_REPO_OWNED_CODESPACES_DISABLED, actor_id: 1)
  end

  test "calls GlobalInstrumenter for enabling organization - ignoring billing owner" do
    GlobalInstrumenter.expects(:instrument).
      once.with(::Codespaces::Events::ORG_REPO_OWNED_CODESPACES_ENABLED, { organization_id: 1, actor_id: 1 })

    Codespaces::OrgSettingsChangedJob.perform_now(context: 1, event_type: ::Codespaces::Events::ORG_REPO_OWNED_CODESPACES_ENABLED, actor_id: 1)
  end

  test "calls GlobalInstrumenter for disabling user" do
    GlobalInstrumenter.expects(:instrument).
      once.with(::Codespaces::Events::ORG_CODESPACES_DISABLED_USER, { user_id: 1, actor_id: 1 })

    Codespaces::OrgSettingsChangedJob.perform_now(context: 1, event_type: ::Codespaces::Events::ORG_CODESPACES_DISABLED_USER, actor_id: 1)
  end

  test "calls GlobalInstrumenter for enabling user" do
    GlobalInstrumenter.expects(:instrument).
      once.with(::Codespaces::Events::ORG_CODESPACES_ENABLED_USER, { user_id: 1, actor_id: 1 })

    Codespaces::OrgSettingsChangedJob.perform_now(context: 1, event_type: ::Codespaces::Events::ORG_CODESPACES_ENABLED_USER, actor_id: 1)
  end
end
