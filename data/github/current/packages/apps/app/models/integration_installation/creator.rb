# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  class Creator
    attr_reader :integration, :target, :repositories, :permissions, :events, :installer, :version, :trigger_id, :entry_point

    attr_reader :skip_callbacks
    alias_method :skip_callbacks?, :skip_callbacks

    # Result from the IntegrationInstallation creation
    class Result
      class Error < StandardError
        attr_reader :reason
        def initialize(message, reason = nil)
          @reason = reason
          super(message)
        end
      end

      def self.success(installation) new(:success, installation: installation) end
      def self.failed(error, reason = nil) new(:failed, error: error, reason: reason) end

      attr_reader :error, :installation, :reason

      def initialize(status, installation: nil, error: nil, reason: nil)
        @status       = status
        @installation = installation
        @error        = error
        @reason       = reason
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    # Public: Give an integration access to repositories
    #
    # integration   - The Integration being installed.
    # target        - The User or Organization account that the integration is
    #                 being installed on.
    # repositories: - An Array of Repositories to include in the installation. (Optional.).
    #                 Pass nil or empty Array to install on all repositories.
    #                 Pass the symbol :none to install this App on no repositories.
    # installer:    - The User performing the installation.
    # version       - The IntegrationVersion used for permissions and events.
    # skip_callbacks - skip calling callbacks after the installation is created,
    #                 allowing the caller to trigger the callbacks as required.
    # pending_request - the IntegrationInstallationRequest that triggered the creation (Optional).
    #
    # Returns an IntegrationInstallation::Creator::Result.
    def self.perform(integration, target, **options)
      T.unsafe(self).new(integration, target, **options).perform
    end

    def initialize(integration, target, installer:, version:, **options)
      @integration   = integration
      @version       = version
      @target        = target
      if options[:repositories] == :none
        @no_repository_installs = true
        @repositories = []
      else
        @no_repository_installs = false
        @repositories  = Array(options[:repositories])
      end
      @permissions   = version.default_permissions
      @events        = version.default_events
      @installer     = installer
      @skip_callbacks = options.fetch(:skip_callbacks, false)
      @trigger_id = options[:trigger_id]
      @pending_request = options[:pending_request]
      @reinstalling_during_repository_transfer = options[:reinstalling_during_repository_transfer]
      @entry_point = options[:entry_point]
    end

    def installing_on_no_repositories?
      !!@no_repository_installs
    end

    def installing_on_all_repositories?
      return false if installing_on_no_repositories?
      @repositories.blank?
    end

    def installing_on_select_repositories?
      return false if installing_on_no_repositories?
      @repositories.any?
    end

    def reinstalling_during_repository_transfer?
      !!@reinstalling_during_repository_transfer
    end

    def perform
      GitHub.tracer.in_span("IntegrationInstallation::Creator#perform", kind: :internal) do
        validate_installer_has_permission

        perform_without_mutation
      end

      after_created_callbacks unless skip_callbacks?
      GitHub.dogstats.increment("integration_installation.create", tags: ["result:success"])

      set_cache

      Result.success(@installation)
    rescue Result::Error => e
      @installation.destroy if @installation && @installation.persisted?

      GitHub.dogstats.increment("integration_installation.create", tags: ["result:failed"])
      Result.failed e.message, e.reason
    end

    def after_created_callbacks
      instrument_installation_created
      UpdateIntegrationInstallationRateLimitJob.perform_later(@installation.id)
    end

    private

    def perform_without_mutation
      @installation = create_installation!

      ApplicationRecord::Permissions.transaction do
        if can_have_repositories?(target)
          if installing_on_all_repositories?
            GitHub.tracer.in_span("#set_permission_for_all_repositories", kind: :internal) do
              set_permission_for_all_repositories
            end
          else
            GitHub.tracer.in_span("#install_on_repositories", kind: :internal) do
              install_on_repositories
            end
          end
        end

        set_org_permissions      if target.is_a?(Organization)
        set_business_permissions if target.is_a?(Business)
      end
    end

    def set_cache
      @installation.set_cached_repository_selection
    end

    def can_have_repositories?(target)
      target.is_a?(User)
    end

    def create_installation!
      options = {}.tap do |opts|
        opts[:target_id]                      = target.id
        opts[:target_type]                    = target.class.to_s
        opts[:integration_version_id]         = version.id
        opts[:integration_version_number]     = version.number
        opts[:subscription_item_id]           = marketplace_subscription_item&.id
        opts[:integration_install_trigger_id] = trigger_id

        if events.any?
          opts[:events] = events
        end
      end

      new_installation = integration.installations.build(options)
      begin
        if ActiveRecord::Base.connected_to(role: :writing) { new_installation.save! }
          marketplace_subscription_item&.record_marketplace_installation
          new_installation
        end
      rescue ActiveRecord::RecordInvalid
        raise Result::Error, new_installation.errors.full_messages.to_sentence
      rescue ActiveRecord::RecordNotUnique
        raise Result::Error.new("this app has already been installed", :already_installed)
      end
    end

    # Private: Check for an active Marketplace subscription for the installation target
    #
    # If the target is a User, there may be an active subscription to a Marketplace
    # listing for this integration. If so, record the subscription ID with the new
    # installation so the installation can be associated with a Marketplace purchase.
    #

    # Returns the Billing::SubscriptionItem or nil if there is no active subscription.
    def marketplace_subscription_item
      return nil unless target.is_a?(User)

      marketplace_listing_plans_ids = Marketplace::ListingPlan.joins(:listing)
        .where(marketplace_listings: {
          listable_id: integration.id,
          listable_type: Marketplace::Listing::INTEGRATION_TYPE,
        }).pluck(:id)

      Billing::SubscriptionItem
        .for_users_on_marketplace_listing_plans(
          user_ids: [target.id],
          listing_plans_ids: marketplace_listing_plans_ids,
        ).first
    end

    def validate_installer_has_permission
      # TODO - Who is installer for launch app?
      # If it is pusher, installer shouldn't be permitted to install app unless
      # they are the repo owner
      options = {
        integration: integration,
        actor:       installer,
        action:      :install,
        target:      target,
        version:     version,
      }

      if installing_on_all_repositories?
        options[:repository_selection] = Integration::Permissions::RepositorySelection::All
      else
        options[:repository_ids] = repositories.map(&:id)
        options[:repository_selection] = Integration::Permissions::RepositorySelection::Subset
      end

      result = Integration::Permissions.check(**options)

      return true if result.permitted?
      raise Result::Error.new(result.error_message, result.reason)
    end

    def validate_repository_is_not_being_transferred(repository)
      return unless repository.transfer_in_progress?

      # Certain Apps should be reinstalled during repository transfers
      # See https://github.com/github/github/pull/128160 for full context
      unless reinstalling_during_repository_transfer?
        raise Result::Error, "Could not complete installation. Please verify repository selection and try again."
      end
    end

    def install_on_repositories
      grant_permissions_on(subjects: repositories, permissions: repository_permissions)
    end

    def set_permission_for_all_repositories
      rows = repository_permissions.map do |resource, action|
        subject = target.repository_resources.public_send(resource.to_s)
        ::Permissions::Service.installation_attributes_hash(actor: @installation, subject: subject, action: action)
      end
      ::Permissions::Service.grant_permissions!(rows, entry_point: @entry_point)
    end

    def instrument_installation_created
      payload = @installation.event_payload.merge(
        installer_id: audit_log_installer_actor.id,
        requester_id: @pending_request&.requester_id,
      )

      if @installation.installed_automatically?
        payload[:installed_automatically] = true
        payload[:trigger_id] = @installation.integration_install_trigger_id
      end

      instrumentation_config = {
        repositories: @repositories,
        audit_log_installer: audit_log_installer_actor,
        installing_on_all: installing_on_all_repositories?,
        installing_on_select: installing_on_select_repositories?
      }
      instrumenter = Apps::InstallationInstrumenter.new(@installation)
      instrumenter.instrument_creation(payload, instrumentation_config)

      GlobalInstrumenter.instrument "integration_installation.create", payload
    end

    def set_business_permissions
      GitHub.tracer.in_span("#set_business_permissions", kind: :internal) do
        grant_permissions_on(subjects: [target], permissions: @version.permissions_of_type(Business))
      end
    end

    def set_org_permissions
      GitHub.tracer.in_span("#set_org_permissions", kind: :internal) do
        grant_permissions_on(subjects: [target], permissions: @version.permissions_of_type(Organization))
      end
    end

    # Internal: Grant permissions to a set of subjects
    # in batch rather than one at a time.
    #
    # subjects    - An Array of Repository|Business|Organization objects.
    # permissions - A Hash of permissions.
    #
    # Returns nothing.
    def grant_permissions_on(subjects:, permissions:)
      rows = subjects.flat_map do |subject|
        if subject.is_a?(Repository)
          validate_repository_is_not_being_transferred(subject)
        end

        permissions.map do |resource, action|
          resource_subject = subject.resources.public_send(resource)
          ::Permissions::Service.app_attributes(actor: @installation, subject: resource_subject, action: action)
        end
      end

      ::Permissions::Service.grant_permissions(rows, entry_point: @entry_point)
    end

    def repository_permissions
      return @repository_permissions if defined?(@repository_permissions)
      @repository_permissions = version.permissions_of_type(Repository)

      if Apps::Privileged.capable?(:static_installation_repository_permissions, app: integration)
        @repository_permissions = Apps::Privileged.property(:static_installation_repository_permissions, app: integration)
      end

      @repository_permissions
    end

    def audit_log_installer_actor
      return @audit_log_installer_actor if defined?(@audit_log_installer_actor)
      @audit_log_installer_actor = @installation.installed_automatically? ? integration.bot : installer
    end
  end
end
