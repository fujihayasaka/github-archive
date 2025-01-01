# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrantRequest
  class Service
    include ActiveModel::Model
    include GitHub::Memoizer

    ATTRIBUTE_DEFAULTS = {
      permissions: {},
      repositories: [],
      repository_selection: :none,
    }

    MAX_REPOSITORY_LIMIT = 50
    BATCH_SIZE = 100

    attr_accessor :target, :access, :actor, :grant, :request, :requests, :request_ids, :permissions, :repositories,
      :repository_selection, :skip_approval_notification
    attr_accessor :request_reason, :request_denied_reason, :entry_point

    validates_presence_of :target, message: "must exist", on: [:create, :approve, :bulk_approve, :deny, :bulk_deny, :cancel]
    validates_presence_of :access, message: "must exist", on: [:create, :approve]
    validates_presence_of :actor,  message: "must exist", on: [:create, :approve, :bulk_approve, :deny, :bulk_deny, :cancel]

    validates_presence_of :entry_point, message: "must be provided", on: [:approve, :bulk_approve]

    validate :actor_can_access_target, on: [:create]

    validate :actor_can_approve_request, on: [:approve]
    validate :actor_can_approve_requests, on: [:bulk_approve]
    validate :actor_can_deny_request, on: [:deny]
    validate :actor_can_deny_requests, on: [:bulk_deny]
    validate :actor_can_cancel_request, on: [:cancel]

    validates_inclusion_of :repository_selection, in: ProgrammaticAccessGrant::RepositorySelection::OPTIONS, on: [:create]

    validate :requested_permissions_are_valid, on: [:create]

    validates_length_of :repositories, within: 1..MAX_REPOSITORY_LIMIT,
      too_short: "please select at least one",
      too_long: "please select no more than #{MAX_REPOSITORY_LIMIT}",
      if: :granting_access_to_subset_of_repositories?, on: [:create]

    validate :all_repositories_belong_to_target, if: -> do
      @target.present? && @repositories.any?
    end, on: [:create, :approve, :bulk_approve]

    validate :no_repository_transfers_in_progress, if: -> do
      @repositories.any?
    end, on: [:create, :approve, :bulk_approve]

    validate :all_repositories_accessible_to_actor, if: -> do
      @target.present? && @repositories.any?
    end, on: [:create]

    # Set default values for expected attributes. This is the recommended pattern
    # from https://api.rubyonrails.org/classes/ActiveModel/Model.html.
    def initialize(attributes = {})
      super

      ATTRIBUTE_DEFAULTS.each do |attr, default_value|
        ivar = "@#{attr}".to_sym

        next if instance_variable_get(ivar)
        instance_variable_set(ivar, default_value)
      end
    end

    def self.create(attributes = {})
      new(attributes).create
    end

    # Creates a new request with the given attributes.
    #
    # Returns an OrganizationProgrammaticAccessGrantRequest object.
    def create
      @request = new_request

      if self.invalid?(:create)
        @request.errors.merge!(self.errors)
        return @request
      end

      begin
        ApplicationRecord::Permissions.transaction do
          @request.save!
          grant_permissions!(@request)
        end
        @request.instrument_creation
        @request.generate_webhook_payload(
          action: :created,
          current_actor: @actor,
          token_expires_at: @access.expires_at
        )
        @request.queue_webhook_delivery
      rescue ActiveRecord::ActiveRecordError => e
        report_and_add_errors(@request, e) if @request.errors.none?
      end

      @request
    end

    def self.approve(request, actor, skip_approval_notification: false, entry_point:)
      # The `repositories` attribute is only set for :subset repo selections.
      # For :subset selections the permissions are written per repository
      # so the repositories need to be validated.
      # These validations can be skipped for :all repo selections.
      repositories = ATTRIBUTE_DEFAULTS[:repositories]
      repository_selection = request.repository_selection.to_sym
      repositories = request.repositories if repository_selection == :subset
      attributes = {
        request: request,
        access: request.user_programmatic_access,
        target: request.target,
        actor: actor,
        grant: request.grant,
        permissions: request.permissions,
        repositories: repositories,
        repository_selection: repository_selection,
        skip_approval_notification: skip_approval_notification,
        entry_point: entry_point
      }

      new(attributes).approve
    end

    # Approves the given request.
    # If a grant exists for the request, transfer permissions to the grant.
    # Otherwise, create a new grant and transfer permissions.
    # Destroys the request if successful.
    #
    # Returns an (Organization|User)ProgrammaticAccessGrant
    def approve
      @grant = @grant || new_grant

      if self.invalid?(:approve)
        @grant.errors.merge!(self.errors)
        return @grant
      end

      begin
        ApplicationRecord::Permissions.transaction do
          @grant.save!

          @request.generate_webhook_payload(action: :approved, current_actor: @actor)
          Permission.where(actor_id: @grant.ability_id, actor_type: @grant.ability_type).delete_all
          update_permissions(@request, @grant, entry_point: entry_point)
          @grant.instrument_granting

          @request.destroy!
          @request.queue_webhook_delivery
        end
      rescue ActiveRecord::ActiveRecordError => e
        report_and_add_errors(@grant, e) if @grant.errors.none?
      end

      notify_decision(:request_approved) if @grant.errors.none? && !skip_approval_notification
      @grant
    end

    def self.bulk_approve(request_ids, actor, target, entry_point:)
      attributes = {
        request_ids: request_ids,
        actor: actor,
        target: target,
        entry_point: entry_point
      }

      new(attributes).bulk_approve
    end

    # Approves requests in bulk
    #
    # Returns self
    def bulk_approve
      @requests = fetch_requests
      # The `repositories` attribute is only set for :subset repo selections.
      # For :subset selections the permissions are written per repository
      # so the repositories need to be validated.
      # These validations can be skipped for :all repo selections.
      @repositories = @requests
        .select { |r| r.repository_selection.to_sym == :subset }
        .map(&:repositories)
        .flatten
        .uniq
      return self if self.invalid?(:bulk_approve)

      BulkApproveProgrammaticAccessGrantRequestsJob.perform_later(
        @target,
        @requests.map(&:id).sort,
        @actor.ability_delegate,
        entry_point: entry_point
      )

      self
    end

    def self.deny(request, actor, reason = nil)
      attributes = {
        request: request,
        access: request.user_programmatic_access,
        actor: actor,
        target: request.target,
        request_denied_reason: reason,
      }

      new(attributes).deny
    end

    # Denies by destroying the given request
    #
    # Returns a request
    def deny
      if self.invalid?(:deny)
        @request.errors.merge!(self.errors)
        return @request
      end

      begin
        @request.generate_webhook_payload(action: :denied, current_actor: @actor)
        @request.deny!(reason: request_denied_reason)
        @request.queue_webhook_delivery
      rescue ActiveRecord::ActiveRecordError => e
        report_and_add_errors(@request, e) if @request.errors.none?
      end

      notify_decision(:request_denied) if @request.errors.none?
      @request
    end

    def self.bulk_deny(request_ids, actor, target)
      attributes = {
        request_ids: request_ids,
        actor: actor,
        target: target,
      }

      new(attributes).bulk_deny
    end

    # Denies by destroying the given request
    #
    # Returns self
    def bulk_deny
      @requests = fetch_requests
      return self if self.invalid?(:bulk_deny)

      BulkDenyProgrammaticAccessGrantRequestsJob.perform_later(
        @target,
        @requests.map(&:id).sort,
        @actor.ability_delegate
      )

      self
    end

    def self.cancel(request, actor)
      new(request: request, actor: actor, target: request.target).cancel
    end

    def cancel
      if self.invalid?(:cancel)
        @request.errors.merge!(self.errors)
        return @request
      end

      @request.generate_webhook_payload(action: :cancelled, current_actor: @actor)
      destroyed = @request.cancel
      @request.queue_webhook_delivery if destroyed

      @request
    end

    # Public: Find all the repositories that the `actor` can request access to
    # for the given target.
    #
    # Returns an Array.
    def self.accessible_repository_ids_on_by(target, actor)
      return [] unless actor && target
      return [] if target.instance_of?(Business)

      target_repository_ids = target.repository_ids
      return target_repository_ids if target.adminable_by?(actor)
      return target.all_org_repo_ids_for_user(actor) if target.instance_of?(Organization)

      []
    end

    private

    def can_request_access_to_target?
      return false unless @target.is_a?(Organization)
      return false if @target.adminable_by?(@actor)

      @target.member?(@actor)
    end

    def actor_can_approve_request
      return true if @request.approvable_by?(@actor)

      self.errors.add(:actor, message: "must have sufficient permissions to approve this request")
    end

    def actor_can_approve_requests
      return true if @requests.all? { |request| request.approvable_by?(@actor) }

      self.errors.add(:actor, message: "must have sufficient permissions to approve requests")
    end

    def actor_can_deny_request
      return true if @request.writable_by?(@actor)

      self.errors.add(:actor, message: "must have sufficient permissions to deny this request")
    end

    def actor_can_deny_requests
      return true if @requests.all? { |request| request.writable_by?(@actor) }

      self.errors.add(:actor, message: "must have sufficient permissions to deny requests")
    end

    def fetch_requests
      ProgrammaticAccessGrantRequest.
        from_target_and_ids(@target, @request_ids).
        preload(user_programmatic_access: [:owner])
    end

    def actor_can_cancel_request
      return true if @request.actor == @actor

      self.errors.add(:actor, message: "must have sufficient permissions to cancel this request")
    end

    # Reports to Sentry and adds the ActiveRecord error to the record
    # Used when permissions fail to write
    #
    # Returns nothing
    def report_and_add_errors(record, error)
      Failbot.report!(error)
      record.errors.add(:base, :write_failed, message: "an unknown error has occurred, please try again")
    end

    # Internal: An ActiveModel validation that ensures that every repository
    # selected for grant is owned by the @target account.
    #
    # Returns a Boolean.
    def all_repositories_belong_to_target
      found_repository_ids = case @target
      when Organization
        Repositories::Public.filter_repo_ids_to_org(repo_ids: repository_ids, organization_id: T.must(@target.id))
                            .pluck(:id)
      else
        @target.associated_repository_ids(repository_ids: repository_ids, including: [:owned])
      end

      return true if repository_ids.difference(found_repository_ids).none?
      errors.add(:repositories, :incorrect_target, message: "one or more requested do not belong to the @#{@target.display_login} account")

      false
    end

    def all_repositories_accessible_to_actor
      associated_repository_ids = Repositories::Public.accessible_repositories(
        repository_ids: repository_ids,
        associated_repository_ids: @actor.associated_repository_ids(repository_ids: repository_ids)
      ).pluck(:id)

      return true if repository_ids.difference(associated_repository_ids).none?
      errors.add(:repositories, :not_accessible, message: "one or more requested are not accessible to you")

      false
    end

    # Internal: Generate all of the Programmatic fine grained permissions
    # and then write them to the `permissions` table.
    #
    # Returns nothing.
    def grant_permissions!(actor)
      rows = grantable_repository_permissions(actor: actor)

      # Grant target permissions "members" => :read or "emails" => :write.
      rows.concat(grantable_permissions_for(
        actor: actor, subjects: [@target], permissions: permissions_of_type(@target.class)
      ))

      rows.flatten!

      stats_key = actor.class.to_s.underscore
      ::Permissions::Service.grant_permissions!(rows, stats_key: stats_key, entry_point: entry_point)
    end

    # Internal: Updates the request's permission records with the given grant
    #
    # Returns nothing.
    def update_permissions(request, grant, entry_point:)
      permissions = Permission.where(actor_id: @request.ability_id, actor_type: @request.ability_type)

      Permissions::Service.update_actor_id_and_actor_type_for_permissions(
        permissions: permissions,
        actor_id: @grant.ability_id,
        actor_type: @grant.ability_type,
        timestamp: Time.now.utc,
        entry_point: entry_point
      )
    end

    # Internal: Return all of the grantable permissions for a list subjects and
    # permissions.
    #
    # Example:
    #
    #    >> grant_permissions_for(subjects: [repo], permissions: { "metadata" => :read })
    #    => [
    #         {
    #           actor_id: @fgp_entity.ability_id,
    #           actor_type: @fgp_entity.ability_id,
    #           subject_id: repo.ability_id,
    #           subject_type: "Repository/resources/metadata",
    #           action: :read,
    #           ...
    #         }
    #       ]
    #
    # Returns an Array.
    def grantable_permissions_for(subjects: [], permissions: {}, actor: @grant)
      subjects.flat_map do |subject|
        resource_subject = subject.resources

        permissions.map do |resource, action|
          ::Permissions::Service.installation_attributes_hash(
            actor: actor, subject: resource_subject.public_send(resource), action: action
          )
        end
      end
    end

    # Internal: Return all of Repository type permissions that we are able to
    # grant on the FGP entity.
    #
    # Returns an Array.
    def grantable_repository_permissions(actor:)
      return [] unless granting_access_to_repositories?

      repository_permissions = permissions_of_type(Repository)
      return [] if repository_permissions.empty?

      assigned_permissions = apply_mandatory_permissions(repository_permissions)

      unless granting_access_to_all_repositories?
        return grantable_permissions_for(actor: actor, subjects: @repositories, permissions: assigned_permissions)
      end

      # Granting access to all repositories is a special case because the prefix
      # changes between individual repository access and "target" repository
      # access. The ability_prefix for installing on "all" is
      # "User/repositories/" while granting access to a a single repo is
      # "Repository/".
      subject = @target.repository_resources

      repository_permissions.map do |resource, action|
        ::Permissions::Service.installation_attributes_hash(
          actor: actor, subject: subject.public_send(resource), action: action
        )
      end
    end

    def granting_access_to_repositories?
      @repository_selection != :none
    end

    def granting_access_to_all_repositories?
      @repository_selection == :all
    end

    def granting_access_to_subset_of_repositories?
      @repository_selection == :subset
    end

    def actor_can_access_target
      return if @target&.adminable_by?(@actor)
      return if can_request_access_to_target?

      self.errors.add(:target, message: "must be accessible by the actor")
    end

    def new_grant
      grant_klass = case @target
      when Organization
        OrganizationProgrammaticAccessGrant
      else
        UserProgrammaticAccessGrant
      end

      grant_klass.new(target: @target, user_programmatic_access: @access)
    end

    def new_request
      grant_klass = case @target
      when Organization
        OrganizationProgrammaticAccessGrantRequest
      else
        UserProgrammaticAccessGrantRequest
      end

      grant_klass.new(target: @target, grant: @grant || @access&.grant_for(@target), user_programmatic_access: @access, reason: @request_reason, actor: @actor)
    end

    # Internal: If individual repositories are selected for installation/granting
    # make sure that none of them are in the middle of being transferred to
    # another target.
    #
    # Returns a Boolean.
    def no_repository_transfers_in_progress
      if Repositories::Transfer.any_in_progress?(@repositories.to_a)
        self.errors.add(:repositories, :in_transfer, message: "one or more are in the process of being transferred")
        return false
      end

      true
    end

    def notify_decision(decision)
      UserProgrammaticAccess.notify_owner(
        about: decision,
        accesses: [access],
        owner: access.owner,
        target: request.target,
        reason: request_denied_reason # Nil on approval
      )
    end

    def permissions_of_type(resource_type)
      "#{resource_type}::Resources".constantize.public_send(:filter, @permissions)
    end

    def requested_permissions_are_valid
      extra_keys = @permissions.keys - valid_resource_types

      extra_keys.each do |resource|
        errors.add(:permissions, :invalid_permission, message: "'#{resource}' is not a valid permission", value: resource)
      end

      return false if self.errors[:permissions].any?

      valid_actions = Permission.actions.keys.map(&:to_sym)

      @permissions.each_pair do |resource, action|
        unless valid_actions.include?(action)
          next self.errors.add(:permissions, :invalid_action, message: "'#{action}' is not a valid action", value: action)
        end

        case action
        when :read
          next unless Permissions::ResourceRegistry.writeonly_subject_type?(resource)
          self.errors.add(:permissions, :invalid_action, message: "'#{resource}' is only available as 'write'", value: action)
        when :write
          next unless Permissions::ResourceRegistry.readonly_subject_type?(resource)
          self.errors.add(:permissions, :invalid_action, message: "'#{resource}' is only available as 'read'", value: action)
        when :admin
          next if Permissions::ResourceRegistry.adminable_subject_type?(resource)
          self.errors.add(:permissions, :invalid_action, message: "'#{resource}' is not available as 'admin'", value: action)
        end
      end
    end

    def valid_resource_types
      Business::Resources.subject_types + \
        Organization::Resources.subject_types + \
        Repository::Resources.subject_types + \
        User::Resources.subject_types
    end

    # Internal: adds resource-specific mandatory permissions to the given
    # assigned_permissions, based on the selected permissions.
    # E.g. selecting _any_ repository resource permission mandates the
    # selection of the "metadata" permission.
    #
    # assigned_permissions - A Hash of resource Strings to permission Symbols.
    #
    # Returns Hash of permissions to be assigned.
    def apply_mandatory_permissions(assigned_permissions)
      if (Repository::Resources.subject_types & assigned_permissions.keys).any?
        assigned_permissions["metadata"] = :read
      end
      assigned_permissions
    end

    memoize def repository_ids
      @repositories.map(&:id)
    end
  end
end
