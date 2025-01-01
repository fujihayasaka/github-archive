# typed: true
# frozen_string_literal: true

class Integration
  class InstallationService
    include Scientist

    attr_reader :integration, :target, :actor, :pending_request, :max_installable, :version
    attr_reader :install_target, :selected_repository_ids, :installation, :entry_point

    # Result from the IntegrationInstallationRequest and IntegrationInstallation creation
    class Result
      class Error < StandardError; end

      def self.success(installation_result:, request_result:)
        new(:success, installation_result: installation_result, request_result: request_result)
      end

      def self.failed(error) new(:failed, error: error) end

      attr_reader :error, :installation_result, :request_result

      def initialize(status, installation_result: nil, request_result: nil, error: nil)
        @status = status
        @installation_result = installation_result
        @request_result = request_result
        @error = error
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    # Limit the number of repositories that can be installed during initial
    # installation.
    DEFAULT_MAX_REPOS = 100

    # Public: Coordinate attempting installation and requesting installation.
    #
    # integration:     - The Integration being installed and/or requested.
    # installation:    - If an installation exists, it will get edited instead
    #                    of creating a new installation.
    # target:          - The User or Organization account that the integration is
    #                    being installed on.
    # actor:           - The User requesting/performing the installation.
    # pending_request: - The pending installation request being approved.
    #                    (Optional, ignored if the actor cannot install & approve requests.)
    # params:          - The safe Hash of params used to install/request.
    #                    :install_target: repository targets for this installation: :all, :selected or :none
    #                    :integration_installation: a hash containing form fields
    #                    :repository_ids: list of repositories to install if :install_target == :selected
    #                    :version_id: the IntegrationVersion ID to install on
    # max_installable: - The max number of repositories that can be installed.
    # editor:          - Specify whether to specifically use the `IntegrationInstallation::RepositoryEditor`
    #                    by passing in `:repository_editor`, or use the default `IntegrationInstallation::Editor`.
    # entry_point:     - The entry_point to log with the Permission Cluster changes.
    #
    # Returns an Integration::InstallationService::Result.
    def self.perform(integration:, target:, actor:, installation: nil, pending_request: nil, params:, max_installable: DEFAULT_MAX_REPOS, editor: :editor, entry_point:)
      new(
        integration: integration,
        installation: installation,
        target: target,
        actor: actor,
        pending_request: pending_request,
        params: params,
        max_installable: max_installable,
        editor: editor,
        entry_point: entry_point,
      ).perform
    end

    def initialize(integration:, target:, actor:, installation: nil, pending_request: nil, params:, max_installable: DEFAULT_MAX_REPOS, editor: :editor, entry_point:)
      @integration = integration
      @installation = installation
      @target = target
      @actor = actor
      @pending_request = pending_request
      @max_installable = max_installable
      @editor = editor

      @install_target = params[:install_target]
      @selected_repository_ids = Array.wrap(params[:repository_ids])
      @version = selected_version(params[:version_id])
      @entry_point = entry_point
    end

    INSTALL_ALL_REPOS = nil
    INSTALL_NO_REPOS = :none

    ResultTypes = T.type_alias do
      T.any(
        IntegrationInstallation::Editor::Result,
        IntegrationInstallation::RepositoryEditor::Result,
        IntegrationInstallation::Creator::Result
      )
    end

    EditorTypes = T.type_alias do
      T.any(
        IntegrationInstallation::Editor,
        IntegrationInstallation::RepositoryEditor
      )
    end

    def perform
      GitHub.tracer.in_span("Integration::InstallationService#perform", kind: :internal) do
        validate_actor_has_verified_email
        validate_install_target
        validate_selected_repositories

        installable = installable?
        requestable = requestable?

        if INSTALL_TARGET_SELECTED == install_target
          # when editing existing installations, allow an empty list of installation repositories,
          # allowing the installation editor to decide how to interpret
          installable = installable && installable_repositories.any? if installation.blank?
          requestable = requestable && requestable_repositories.any?
        end

        editor = T.let(nil, T.nilable(EditorTypes))
        creator = T.let(nil, T.nilable(IntegrationInstallation::Creator))
        installation_result = T.let(nil, T.nilable(ResultTypes))
        request_result = T.let(nil, T.nilable(IntegrationInstallationRequest))

        # See https://github.com/github/github/pull/123290 for more context
        unless installable || requestable || target.adminable_by?(actor)
          raise Result::Error, ORG_OWNER_ACTION_ERR
        end

        ApplicationRecord::Permissions.transaction do
          integration.transaction do
            if installable
              installation_result =
                if installation
                  editor = build_editor
                  editor.perform
                else
                  creator = build_creator
                  creator.perform
                end

              if installation_result.failed?
                raise Result::Error, installation_result.error
              end

              pending_request.close(reason: :approved, actor: actor) if pending_request.present?
            end

            if requestable
              request_result = IntegrationInstallationRequest.create(
                requester: actor,
                integration: integration,
                target: target,
                repositories: requestable_repositories,
              )

              if !request_result.valid?
                raise Result::Error, request_result.errors.full_messages.to_sentence
              end
            end
          end
        end

        editor.after_updated_callbacks if editor.present?
        creator.after_created_callbacks if creator.present?

        Result.success(
          installation_result: installation_result,
          request_result: request_result,
        )
      rescue Result::Error => e
        Result.failed e.message
      end
    end

    # Public: The selected repositories that the actor has access to.
    #
    # Returns a Repository ActiveRecord::Relation scoped to the selected
    # repositories this actor has access to.
    def selected_repositories
      return Repository.none if [INSTALL_TARGET_ALL, INSTALL_TARGET_NONE].include?(install_target)
      return @selected_repositories if defined?(@selected_repositories)

      # filter for accessible repositories. Only target members can additionally select public repos.
      if target.organization? && !target.member?(actor)
        scope = target.repositories.where(id: accessible_selected_repository_ids)
      else
        scope = target.repositories.where(
          "repositories.public = ? OR repositories.id IN (?)",
          true,
          accessible_selected_repository_ids,
        )
      end

      # but only return the repositories explicitly requested
      scope = scope.where(id: selected_repository_ids)

      @selected_repositories = scope
    end

    # Internal: The selected repository IDs that this actor has access to.
    #
    # NOTE: when the actor is targeting self, returns the given IDs unfiltered
    # as those will be properly filtered by owner in `selected_repositories`.
    #
    # Returns an Array of IDs.
    def accessible_selected_repository_ids
      @accessible_selected_repository_ids ||=
        if target == actor
          selected_repository_ids
        else
          filtered_selected_repository_ids
        end
    end

    # Internal: Loads the repo id's the actor has access to
    # from the selected repositories.
    def filtered_selected_repository_ids
      # repo abilities
      non_admin_ability_repo_ids = selected_repository_abilities.pluck(:subject_id)
      # we already know they have access to all the possible repositories
      return non_admin_ability_repo_ids if non_admin_ability_repo_ids.count == selected_repository_ids.count

      # repos the user doesn't already have a non admin ability on
      # but potentially has access via being an org admin
      remaining_repos = selected_repository_ids - non_admin_ability_repo_ids
      adminable_repo_ids = Repository.accessible_via_org_admin(actor, remaining_repos)

      repo_ids = non_admin_ability_repo_ids + adminable_repo_ids
      repo_ids.uniq
    end

    def selected_repository_abilities
      @selected_repository_abilities ||= Authorization.service.most_capable_collaborator_abilities_from_actor(
        actor: actor,
        subject_type: Repository,
        subject_ids: selected_repository_ids,
      )
    end

    # Internal: The selected repositories that are installable by the actor.
    #
    # When the actor is installing on all or none of the repositories, always
    # return an empty list.
    #
    # If the actor can install on all repositories on the target account,
    # return all of the repositories they've selected.
    #
    # Otherwise, the actor is an organization member. If that organization has
    # not enabled the repo-admin app management feature flag, the member
    # cannot install on any repository so we bail early.
    #
    # Finally, if the target organization has enabled repo-admin app management,
    # we select repositories that the actor is an admin on.
    #
    # Returns a Repository ActiveRecord::Relation.
    def installable_repositories
      # if actor is a non-org owner repo admin, only install on repos they admin
      if INSTALL_TARGET_ALL == install_target && installable? && !integration.installable_on_all_repositories_by?(target: target, actor: actor)
        return Repository.owned_by(target).where({
          # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          id: actor.associated_repository_ids(min_action: :admin),
          # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        })
      end

      # if the actor can install on all of the target repositories, return the full list of selected repositories
      return selected_repositories if integration.installable_on_all_repositories_by?(target: target, actor: actor)

      return @installable_repositories if defined?(@installable_repositories)

      adminable_ids = selected_repository_ids_by_action(action: :admin)

      @installable_repositories =
        if adminable_ids.any?
          target.repositories.where(id: adminable_ids)
        else
          target.repositories.none
        end
    end

    # Returns a Repository ActiveRecord::Relation scoped to the selected
    # repositories this actor has access to.
    def requestable_repositories
      # if the actor can install on all of the target repositories, return a
      # null relation because the actor can install and does not need to request
      return target.repositories.none if integration.installable_on_all_repositories_by?(target: target, actor: actor)

      return @requestable_repositories if defined?(@requestable_repositories)

      # if the actor can read any of the selected repositories, proceed; otherwise,
      # return a null relation
      readable_ids = selected_repository_ids_by_action(action: :read)
      return @requestable_repositories = target.repositories.none unless readable_ids.any?

      # build scope of repositories that the actor can read
      scope = target.repositories.where(id: readable_ids)

      # exclude repositories that the actor can install on only if the target
      # organization account allows repo-admins to install apps on their adminable repos
      if integration&.repository_permissions_only? &&
         !integration.default_permissions.keys.include?("administration")
        adminable_ids = selected_repository_ids_by_action(action: :admin)
        scope = scope.where.not(id: adminable_ids)
      end

      # exclude repositories that are already installed
      if installation.present?
        scope = scope.where.not(id: installation.repository_ids)
      end

      @requestable_repositories = scope
    end

    # Internal: Returns an Array of repository ID Integers that the actor can
    # `action` on, including public repositories the actor can `read`, from
    # the repositories selected.
    def selected_repository_ids_by_action(action:)
      public_repo_ids =
        if action == :read
          target.repositories.public_scope.where(id: selected_repository_ids).pluck(:id)
        else
          [] # public repos are only implicitly accessible for read
        end

      ids = public_repo_ids
      selected_repository_abilities.each do |ability|
        ids << ability.subject_id if ability.can?(action)
      end

      # add any remaining repo id's accessible via org adminship
      remaining_repo_ids = selected_repository_ids - ids
      ids << Repository.accessible_via_org_admin(actor, remaining_repo_ids) if !remaining_repo_ids.empty?

      ids.flatten.uniq
    end

    def installable?
      return @installable if defined?(@installable)
      @installable = integration.installable_on_by?(target: target, actor: actor)
    end

    def requestable?
      return @requestable if defined?(@requestable)
      @requestable = integration.requestable_on_by?(target: target, actor: actor)
    end

    private

    VALID_INSTALL_TARGETS = %w(all selected none).freeze

    INSTALL_TARGET_ALL      = "all"
    INSTALL_TARGET_NONE     = "none"
    INSTALL_TARGET_SELECTED = "selected"

    SELECT_TARGETS_ERR = "Please select individual or all repositories"
    SELECT_ONE_OR_MORE_ERR = "Please select at least one repository to install on"
    SELECT_MAX_ERR = "Please select less than %d repositories."
    SELECT_OWNERS_ERR = "Repositories must be owned by %s"

    ORG_OWNER_ACTION_ERR = "This action must be performed by an organization owner"

    USER_MUST_VERIFY_EMAIL = "You must have a verified email address in order to install this application"

    def selected_version(version_id)
      integration.versions.find_by_id(version_id) || integration.latest_version
    end

    def validate_actor_has_verified_email
      return unless integration.can_request_oauth_on_install?

      if actor.respond_to?(:must_verify_email?) && actor.must_verify_email?
        raise Result::Error, USER_MUST_VERIFY_EMAIL
      end
    end

    def validate_install_target
      raise Result::Error, SELECT_TARGETS_ERR unless VALID_INSTALL_TARGETS.include?(install_target)

      case install_target
      when INSTALL_TARGET_SELECTED
        # OK, defer validating selected repositories to separate validation
      when INSTALL_TARGET_ALL
        # OK
      when INSTALL_TARGET_NONE
        if integration.repository_installation_required?(@target)
          raise Result::Error, SELECT_TARGETS_ERR
        end
      else
        raise Result::Error, SELECT_TARGETS_ERR
      end
    end

    def validate_selected_repositories
      return unless install_target == INSTALL_TARGET_SELECTED

      installed_repository_count = installation.present? ? installation.repositories_count : 0
      if (selected_repository_ids.length - installed_repository_count) >= max_installable
        raise Result::Error, SELECT_MAX_ERR % max_installable
      end

      if Repository.where(id: selected_repository_ids).where.not(owner_id: target.id).any?
        raise Result::Error, SELECT_OWNERS_ERR % target.display_login
      end

      if installation.blank? && selected_repositories.empty?
        raise Result::Error, SELECT_ONE_OR_MORE_ERR
      end
    end

    def build_editor
      if @editor == :repository_editor
        IntegrationInstallation::RepositoryEditor.new(
          installation,
          :update,
          installable_repositories,
          actor,
          true, # skip_callbacks
          entry_point
        )
      else
        IntegrationInstallation::Editor.new(
          installation,
          repositories: installable_repositories,
          editor: actor,
          pending_request: pending_request,
          skip_callbacks: true,
          entry_point: entry_point
        )
      end
    end

    def build_creator
      IntegrationInstallation::Creator.new(
        integration,
        target,
        version: version,
        installer: actor,
        repositories: installable_repositories,
        skip_callbacks: true,
        pending_request: pending_request,
        entry_point: entry_point
      )
    end

  end
end
