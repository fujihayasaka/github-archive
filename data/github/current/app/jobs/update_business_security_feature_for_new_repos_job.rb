# typed: true
# frozen_string_literal: true

# Updates code security settings for every organization in a business
class UpdateBusinessSecurityFeatureForNewReposJob < ApplicationJob
  queue_as :update_business_security_feature_for_new_repos
  retry_on_dirty_exit

  # Hashlock to ensure one job to be queued per business and type
  locked_by timeout: 60.seconds, key: ->(job) {
    business = job.arguments[0]
    update_type = job.arguments[1]
    "#{business.class.name.underscore}-#{business.id}-#{update_type}"
  }

  before_enqueue do |job|
    business = job.arguments[0]
    JobStatus.create({ id: job.class.job_id(business) })
  end

  sig { params(business: Business).returns(String) }
  def self.job_id(business)
    "#{name}.#{business.class.name}.#{business.id}".underscore
  end

  sig { params(business: Business).returns(T.nilable(JobStatus)) }
  def self.status(business)
    JobStatus.find(job_id(business))
  end

  # Updates a security feature for all organizations in a business
  #
  # business                       - The business to perform the update for
  # update_type                    - The type of security and analysis settings being updated. Can be either:
  #                                  :secret_scanning, :secret_scanning_push_protection,
  #                                  :push_protection_custom_message, push_protection_custom_message_toggle,
  #                                  :advanced_security, or :security_alerts
  # toggle                         - The toggle to enable or disable the security feature, can be either: :enable or :disable
  # actor_id                       - Id of the actor that initiated the job
  # push_protection_custom_message - If update_type is :push_protection_custom_message, the custom message to set
  sig { params(business: Business, update_type: Symbol, toggle: Symbol, actor_id: Integer, push_protection_custom_message: T.nilable(String)).void }
  def perform(business, update_type, toggle, actor_id, push_protection_custom_message: nil)
    job_status = self.class.status(business) || JobStatus.create({ id: self.class.job_id(business) })

    job_status.track do
      actor = User.find(actor_id)

      GitHub.logger.with_named_tags(
        {
          "enduser.id": actor.display_login,
          "gh.enduser.id": actor_id,
          "gh.enduser.login": actor.display_login,
          "gh.business.id": business.id,
          "gh.business.name": business.name,
          "gh.security_products.job.update_type": arguments.dig(1),
          "gh.security_products.job.status.id": job_status.id,
        }
      ) do
        GitHub.logger.info("Job starting", "code.namespace": self.class.name, "code.function": __method__)

        with_write do
          # secret scanning
          if update_type == :secret_scanning && toggle == :enable
            business.organizations.each { |org| SecretScanning::Features::Org::TokenScanning.new(org).enable_secret_scanning_for_new_repos(actor: actor) }
            toggle_for_emus(business, actor, SecretScanning::Features::User::TokenScanning, :enable_secret_scanning_for_new_repos)
          elsif update_type == :secret_scanning && toggle == :disable
            business.organizations.each { |org| SecretScanning::Features::Org::TokenScanning.new(org).disable_secret_scanning_for_new_repos(actor: actor) }
            toggle_for_emus(business, actor, SecretScanning::Features::User::TokenScanning, :disable_secret_scanning_for_new_repos)

          # validity checks
          elsif update_type == :secret_scanning_validity_checks && toggle == :enable
            business.organizations.each { |org| SecretScanning::Features::Org::ValidityChecks.new(org).enable_for_new_repos(actor: actor) }
            toggle_for_emus(business, actor, SecretScanning::Features::User::ValidityChecks, :enable_for_new_repos)
          elsif update_type == :secret_scanning_validity_checks && toggle == :disable
            business.organizations.each { |org| SecretScanning::Features::Org::ValidityChecks.new(org).disable_for_new_repos(actor: actor) }
            toggle_for_emus(business, actor, SecretScanning::Features::User::ValidityChecks, :disable_for_new_repos)

          # push protection
          elsif update_type == :secret_scanning_push_protection && toggle == :enable
            business.organizations.each { |org| SecretScanning::Features::Org::PushProtection.new(org).enable_for_new_repos(actor: actor) }
            toggle_for_emus(business, actor, SecretScanning::Features::User::PushProtection, :enable_for_new_repos)
          elsif update_type == :secret_scanning_push_protection && toggle == :disable
            business.organizations.each { |org| SecretScanning::Features::Org::PushProtection.new(org).disable_for_new_repos(actor: actor) }
            toggle_for_emus(business, actor, SecretScanning::Features::User::PushProtection, :disable_for_new_repos)

          # push protection custom message toggle
          elsif update_type == :push_protection_custom_message_toggle && toggle == :enable
            business.organizations.each { |org| SecretScanning::Features::Org::PushProtection.new(org).enable_custom_message(actor: actor) }
          elsif update_type == :push_protection_custom_message_toggle && toggle == :disable
            # only disable the custom message on orgs that have not overridden the business custom message
            business_custom_message = business.get_push_protection_custom_message
            orgs_to_disable = business.organizations.select { |org| SecretScanning::Features::Org::PushProtection.new(org).custom_message_active? && org.get_push_protection_custom_message == business_custom_message  }
            orgs_to_disable.each { |org| SecretScanning::Features::Org::PushProtection.new(org).disable_custom_message(actor: actor)  }

          # push protection custom message
          elsif update_type == :push_protection_custom_message
            # only update orgs that haven't overridden the business setting
            previous_business_custom_message = business.get_push_protection_custom_message
            orgs_to_update = business.organizations.select { |org| org.get_push_protection_custom_message == previous_business_custom_message }
            orgs_to_update.each { |org| org.set_push_protection_custom_message(push_protection_custom_message, actor) }
            business.set_push_protection_custom_message(push_protection_custom_message, actor)

          # Enable push protection custom message AND set it:
          elsif update_type == :enable_and_set_push_protection_custom_message
            previous_business_custom_message = business.get_push_protection_custom_message

            business.organizations.each do |org|
              # First, ensure that the org has custom message enabled. If it is already enabled this is a no-op:
              SecretScanning::Features::Org::PushProtection.new(org).enable_custom_message(actor: actor)

              # Then, update the message if they haven't overridden the business setting:
              next if org.get_push_protection_custom_message != previous_business_custom_message
              org.set_push_protection_custom_message(push_protection_custom_message, actor)
            end

            business.set_push_protection_custom_message(push_protection_custom_message, actor)

          # advanced security
          elsif update_type == :advanced_security && toggle == :enable
            business.organizations.each { |org| org.enable_advanced_security_on_new_repos(actor: actor) }
          elsif update_type == :advanced_security && toggle == :disable
            business.organizations.each { |org| org.disable_advanced_security_on_new_repos(actor: actor) }

          # security alerts
          elsif update_type == :security_alerts && toggle == :enable
            business.organizations.each { |org| org.enable_security_alerts_for_new_repos(actor: actor) }
          elsif update_type == :security_alerts && toggle == :disable
            business.organizations.each { |org| org.disable_security_alerts_for_new_repos(actor: actor) }
          end
        end

        GitHub.logger.info("Job finished", "code.namespace": self.class.name, "code.function": __method__)
      end
    end
  end

  def toggle_for_emus(business, actor, klass, toggle_method)
    feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(business)
    return unless feature.feature_available_for_user_repositories?

    current_page = 1
    entities = feature.list_enterprise_users_paged(page: current_page, per_page: 1000)

    while entities.length > 0
      entities.each do |entity|
        klass.new(entity).send(toggle_method, actor: actor)
      end

      current_page += 1
      entities = feature.list_enterprise_users_paged(page: current_page, per_page: 1000)

      if current_page > 1000
        GitHub.logger.info("Paging enterprise users has surpassed 1000 pages")
        break
      end
    end
  end
end
