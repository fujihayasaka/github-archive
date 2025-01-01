# typed: true
# frozen_string_literal: true

class EnterpriseUpdateSecurityConfigurationApplicationsJob < ApplicationJob
  include GitHub::Memoizer

  queue_as :security_configurations

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # ProductEnablementChanges example: { dependency_graph: { before: false, after: true } }
  ProductEnablementChanges = T.type_alias { T::Hash[Symbol, T::Hash[Symbol, T::Boolean]] }

  sig { void }
  def perform
    return unless GitHub.enterprise?

    initialize_enablement_cache!

    if product_enablement_changes.blank?
      # No changes found, we don't have to do anything!
      log_message("No product enablement changes, skipping job run.")
      return
    end
    log_message(
      "Security product enablement changed.",
      product_enablement_changes: product_enablement_changes.inspect
    )

    enabled_security_configuration_ids = Set.new

    # When a security product is installed, we will iterate through all RepositorySecurityConfigurations
    # and enqueue an enablement job for all repos that have that product set to enabled or disabled.
    #
    # When a security product is uninstalled we will produce an audit log and take no action.
    product_enablement_changes.each do |feature, states|
      SecurityConfiguration.where(feature => %w(enabled disabled)).find_each do |config|
        # Feature was uninstalled
        if config.send("#{feature}_enabled?") && states[:after] == false
          config.instrument_security_feature_changed(security_feature: feature, security_feature_state: :uninstalled)

        # Feature was installed
        elsif states[:after] == true
          enabled_security_configuration_ids.add(config.id)

          # On GHES, Dependency Graph is a special case where it does not support per-repo enablement.
          # Therefore, when it's installed, we need to enable it on all configurations.
          if feature == :dependency_graph && config.dependency_graph_disabled?
            ActiveRecord::Base.connected_to(role: :writing) do
              unless config.update(dependency_graph: :enabled)
                log_message(
                  "Failed to update SecurityConfiguration to enable Dependency Graph.",
                  security_configuration_id: config.id,
                  errors: config.errors.full_messages,
                  job_id: enqueue.job_id,
                )
              end
            end
          end

          if config.send("#{feature}_enabled?")
            config.instrument_security_feature_changed(security_feature: feature, security_feature_state: :installed)
          end
        end
      end
    end

    if enabled_security_configuration_ids.blank?
      log_message("No SecurityConfigurations matching the enabled security product were found. Exiting!")
      return
    end

    log_message(
      "Found SecurityConfiguration matching enabled product changes.",
      security_configuration_count: enabled_security_configuration_ids.count,
    )

    arel = RepositorySecurityConfiguration.applied.where(security_configuration_id: enabled_security_configuration_ids.to_a)
    arel.find_each(batch_size: 100) do |rsc|
      enqueue = rsc.enqueue_reapply_job(actor_id: User.ghost.id) # FIXME: Which actor goes here?
      log_message(
        "Enqueued ApplySecurityConfigurationToRepositoryJob because of enterprise product enablement change.",
        repository_id: rsc.repository_id,
        security_configuration_id: rsc.security_configuration_id,
        job_id: enqueue.job_id,
      )
    end

    log_message("Successfully completed job!")
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  memoize def services
    SecurityProductsEnablement::SecurityProductsManager.new.services
  end

  sig { void }
  def initialize_enablement_cache!
    services.each do |feature, enabled|
      # setnx will only set values if they're missing,
      # so new features will be populated and existing ones won't get over-written:
      ActiveRecord::Base.connected_to(role: :writing) do
        SecurityProductsEnablement::KV.setnx(key_for_product(feature), enabled.to_s)
      end
    end
  end

  sig { returns(ProductEnablementChanges) }
  memoize def product_enablement_changes
    product_enablement_changes = T.let({}, ProductEnablementChanges)

    services.each do |feature, computed_state|
      # Ensure we read our own writes, because initialize_enablement_cache! might have just written these values:
      kv_state_string = ActiveRecord::Base.connected_to(role: :writing) do
        SecurityProductsEnablement::KV.get(key_for_product(feature)).value!
      end
      cached_state = kv_state_string == "true"

      if cached_state != computed_state
        product_enablement_changes[feature] = { before: cached_state, after: computed_state }

        # Update the cache to ensure it's up-to-date:
        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityProductsEnablement::KV.set(key_for_product(feature), computed_state.to_s)
        end
      end
    end

    product_enablement_changes
  end

  sig { params(product: T.any(Symbol, String)).returns(String) }
  def key_for_product(product)
    "services.#{product}.enabled"
  end

  # When this job is called through `perform_now` in a rake task in GHES,
  # `GitHub.logger.info` won't write to `resqued.log`, and logs can't be found
  # in support bundles. This is because rake tasks in GHES run in the
  # `github-env` container, and logs from this container aren't included
  # in the bundle. So, we also use `puts` to log messages from this job.
  sig { params(message: String, tags: T::Hash[Symbol, T.untyped]).void }
  def log_message(message, tags = {})
    GitHub.logger.info(message, **tags)

    tags[:"code.namespace"] = self.class.name
    puts("#{message} - tags: #{tags}")
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    tags = {
      "code.namespace": self.class.name,
    }

    super.merge(tags)
  end
end
