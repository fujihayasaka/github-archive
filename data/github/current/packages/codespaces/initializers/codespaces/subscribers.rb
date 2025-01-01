# typed: true
# frozen_string_literal: true

Rails.configuration.after_initialize do
  module Codespaces
    class Subscribers
      def attach
        return unless GitHub.codespaces_enabled?

        GlobalInstrumenter.subscribe("billing.plan_change") do |event|
          payload = event.payload

          Codespaces::ProcessPlanChange.call(user_id: payload[:user_id],
                                              old_plan_name: payload[:old_plan_name],
                                              new_plan_name: payload[:new_plan_name])
        end

        GlobalInstrumenter.subscribe(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED) do |event|
          user, repository_ids = event.payload.values_at(:user, :repository_ids)
          Codespaces::FindAffectedCodespacesByRepositoryAccessChange.call(user: user, repository_ids: repository_ids, deletion_reason: Codespace.deletion_reasons[:lost_repo_access])
        end

        GlobalInstrumenter.subscribe(Codespaces::Events::CODESPACE_REPOSITORY_CHANGED) do |event|
          codespace = event.payload[:codespace]
          CodespacesProcessSystemEventJob.perform_later(codespaces: [codespace])
        end

        GlobalInstrumenter.subscribe(Codespaces::Events::CODESPACE_REPOSITORY_CHANGED) do |event|
          codespace = event.payload[:codespace]
          Codespaces::ReassociateUserSecrets::Job.perform_later(codespace: codespace)
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::INACCESSIBLE_CODESPACE) do |event|
          codespace_id = event.payload[:codespace_id]

          next if codespace_id.nil?

          codespace = Codespace.find_by(id: codespace_id)

          next if codespace.nil?

          skip_transfer_billable_owner = GitHub.flipper[:codespaces_skip_transfer_for_inaccessible].enabled?(codespace.owner)
          CodespacesProcessSystemEventJob.perform_later(codespaces: [codespace], transfer_billable_owner: !skip_transfer_billable_owner, deletion_reason: Codespace.deletion_reasons[:inaccessible])
        end

        GlobalInstrumenter.subscribe("repository.visibility_changed") do |event|
          is_private, repository_id = event.payload.values_at(:is_private, :repository_id)

          # We only need to perform inaccessibility clean up in the case of the
          # transition from public -> private not the inverse.
          next unless is_private

          Codespaces::FindAffectedCodespacesByRepository.call(repository_id: repository_id, deletion_reason: Codespace.deletion_reasons[:repository_made_private])
        end

        GlobalInstrumenter.subscribe(GlobalEvents::Repository::REMOVED) do |event|
          repository_id = event.payload[:repository_id]

          Codespaces::FindAffectedCodespacesByRepository.call(repository_id: repository_id, deletion_reason: Codespace.deletion_reasons[:repository_removed])
          Codespaces::HandlePrebuildsWhenRepoDeletedJob.perform_later(repository_id: repository_id)
        end

        GlobalInstrumenter.subscribe("pull_request.create") do |event|
          pull = event.payload[:pull_request]

          next unless pull.present?

          Codespaces::AttachPullRequestJob.perform_later(pull_request: pull)
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_CODESPACES_DISABLED) do |event|
          organization_id = event.payload[:organization_id]

          Codespaces::FindAffectedCodespacesByOrganization.call(
            organization_id: organization_id,
            disabled: true,
            deletion_reason: Codespace.deletion_reasons[:org_disabled_codespaces],
          )

          Codespaces::UpdateTrustedRepositoryAccess.call(
            actor: User.find_by(id: event.payload[:actor_id]),
            target: Organization.find_by(id: organization_id),
            trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED,
            repo: nil,
            entry_point: :codespaces_subscribers_org_codespaces_disabled_event
          )
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_CODESPACES_ENABLED) do |event|
          organization_id = event.payload[:organization_id]

          Codespaces::FindAffectedCodespacesByOrganization.call(organization_id: organization_id)
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_CODESPACES_OWNERSHIP_SETTING_UPDATED) do |event|
          organization_id = event.payload[:organization_id]
          Codespaces::FindAffectedCodespacesByOrganization.call(organization_id: organization_id)
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_REPO_OWNED_CODESPACES_DISABLED) do |event|
          organization_id = event.payload[:organization_id]

          Codespaces::UpdateCodespacesEnablementByOrganization.call(
            organization_id: organization_id,
            disabled: true,
          )

          Codespaces::UpdateTrustedRepositoryAccess.call(
            actor: User.find_by(id: event.payload[:actor_id]),
            target: Organization.find_by(id: organization_id),
            trusted_repo_setting: Configurable::CodespaceTrustedRepositories::DISABLED,
            repo: nil,
            entry_point: :codespaces_subscribers_org_repo_owned_codespaces_disabled_event
          )
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_REPO_OWNED_CODESPACES_ENABLED) do |event|
          organization_id = event.payload[:organization_id]

          Codespaces::UpdateCodespacesEnablementByOrganization.call(organization_id: organization_id)
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_CODESPACES_ENABLED_USER) do |event|
          user_id = event.payload[:user_id]

          Codespaces::FindAffectedCodespacesByUser.call(user_id: user_id)
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_CODESPACES_DISABLED_USER) do |event|
          user_id = event.payload[:user_id]

          Codespaces::FindAffectedCodespacesByUser.call(user_id: user_id, deletion_reason: Codespace.deletion_reasons[:org_disabled_for_user])
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_CODESPACES_ENABLED_TEAM) do |event|
          team_id = event.payload[:team_id]

          Codespaces::FindAffectedCodespacesByTeam.call(team_id: team_id)
        end

        GlobalInstrumenter.subscribe(::Codespaces::Events::ORG_CODESPACES_DISABLED_TEAM) do |event|
          team_id = event.payload[:team_id]

          Codespaces::FindAffectedCodespacesByTeam.call(team_id: team_id, deletion_reason: Codespace.deletion_reasons[:org_disabled_for_team])
        end

        GlobalInstrumenter.subscribe("user.logout") do |event|
          user = event.payload[:actor]
          time_left = event.payload[:request_time_left]

          next unless user && time_left

          # don't use up all the request time, pad an extra second for other stuff
          time_left -= 1.0
          next if time_left.negative?

          Codespaces::LightweightWebEditor.revoke_all_tokens(user: user, timeout: time_left, entry_point: :codespaces_subscribers_user_logout_event)
        end

        GitHub.subscribe("user.suspend") do |event|
          Codespaces::HandleSpammyUser.call(
            user_id: event.payload[:user_id],
            user_type: "User"
          )
        end

        GitHub.subscribe("org.suspend") do |event|
          Codespaces::HandleSpammyUser.call(
            user_id: event.payload[:org_id],
            user_type: "Organization"
          )
        end

        GlobalInstrumenter.subscribe("organization.create") do |event|
          org = event.payload[:organization]
          org.set_organization_codespaces_ownership_setting_for_new_org
        end

        GitHub.subscribe "staff.mark_as_spammy" do |event|
          payload = event.payload.slice(:user_type, :user_id, :org_id)
          Codespaces::HandleSpammyUser.call(
            user_id: payload[:user_id] || payload[:org_id],
            user_type: payload[:user_type]
          )
        end

        GlobalInstrumenter.subscribe("search_indexing.repository_changed") do |event|
          change, repository = event.payload.values_at(:change, :repository)

          next unless repository && change == :OWNER_CHANGED
          next unless Codespaces::PrebuildTemplate.exist_on_repo?(repository.id)

          Codespaces::TransferPrebuildTemplateOwnerByRepositoryJob.perform_later(repository: repository)
        end

        GlobalInstrumenter.subscribe("prebuild_configuration_workflow_run.update") do |event|
          prebuild_configuration = Codespaces::PrebuildConfiguration.find_by(id: event.payload[:prebuild_configuration_id])
          next unless prebuild_configuration

          workflow_run = Actions::WorkflowRun.find_by(id: prebuild_configuration.latest_workflow_run_id)
          next unless workflow_run

          GitHub::WebSocket.notify_prebuild_configuration_workflow_run_channel(
            prebuild_configuration,
            GitHub::WebSocket::Channels.prebuild_configuration_workflow_run(prebuild_configuration)
          )
        end

        GlobalInstrumenter.subscribe("prebuild_repository_check_suite.update") do |event|
          check_suite = CheckSuite.find_by(id: event.payload[:check_suite_id], repository_id: event.payload[:repository_id])
          next unless check_suite && check_suite.workflow_run

          prebuild_configuration = Codespaces::PrebuildConfiguration.find_by(latest_workflow_run_id: T.must(check_suite.workflow_run).id)
          next unless prebuild_configuration

          GitHub::WebSocket.notify_prebuild_configuration_workflow_run_channel(
            prebuild_configuration,
            GitHub::WebSocket::Channels.prebuild_configuration_workflow_run(prebuild_configuration)
          )
        end

        GlobalInstrumenter.subscribe(/repository_secret\.(create|update|remove)/) do |event|
          payload = event.payload
          repository = payload[:owner]
          next unless is_codespace_app?(payload[:app])

          Codespaces::ProcessRepositorySecretUpdatesJob.perform_later(repository: repository)
        end

        GlobalInstrumenter.subscribe(/user_secret\.(create|update|remove)/) do |event|
          payload = event.payload
          selected_repository_global_ids = payload[:selected_repositories]
          user = payload[:owner]
          next unless is_codespace_app?(payload[:app])

          Codespaces::ProcessUserSecretUpdatesJob.perform_later(selected_repository_global_ids: selected_repository_global_ids, user: user)
        end

        GlobalInstrumenter.subscribe(/org_secret\.(create|update|remove)/) do |event|
          payload = event.payload
          selected_repository_global_ids = payload[:selected_repositories]
          org = payload[:owner]
          next unless is_codespace_app?(payload[:app])

          Codespaces::ProcessOrgSecretUpdatesJob.perform_later(selected_repository_global_ids: selected_repository_global_ids, org: org)
        end
      end

      private

      def is_codespace_app?(app)
        app == ::Apps::Internal.integration(:codespaces_production)
      end
    end
  end

  Codespaces::Subscribers.new.attach
end
