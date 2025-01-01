# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AppOwner
    sig { params(user: User).returns(Spark::RuntimeAppOwner) }
    def self.ensure_owner(user)
      # Look for the existing owner for the user
      owner = Spark::RuntimeAppOwner.find_by(owner_id: user.id)
      if owner
        # Handle the case where the user has changed their display login
        # To be reworked in https://github.com/github/spark/issues/1335
        if owner.last_seen_login != user.display_login
          # We can only handle updates if the user is in the new ACA API
          if !SparkRuntime::OwnerApiKV.is_new_api_version?(owner.permanent_name)
            raise SparkRuntime::SparkRuntimeError.new "User is not using the new ACA API, cannot update display login"
          end

          response = SparkRuntime::AcaUserManagementClient.new(user, owner, true).put_user
          if !response.call_succeeded?
            # If we fail to update the user, we will raise an error. In development, we can
            # ignore this error because the developer may not have the appropriate ACA tokens in the environment
            # and the `monalisa` user should already be set-up anyways.
            is_development = Rails.env && Rails.env.development?
            raise SparkRuntime::SparkRuntimeError.new "Failed to update ACA user" unless is_development
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            owner.update!(
              last_seen_login: user.display_login,
              deploy_login: compliant_name(user)
            )
          end
        end

        return owner
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        Spark::RuntimeAppOwner.create!(
          owner_id: user.id,
          permanent_name: Spark::RuntimeApp.generate_random_name,
          last_seen_login: user.display_login,
          # The deploy_login houses the custom username that's visible in the ACA deployment.
          deploy_login: compliant_name(user)
        )
      end
    end


    sig { params(user: User).returns(String) }
    private_class_method def self.compliant_name(user)
      if Naming::is_aca_compliant_name?(user.display_login)
        user.display_login
      else
        mangled = SparkRuntime::Naming.generate_unique_user_name(user.display_login)
        log_mangling(user, mangled)
        mangled
      end
    end

    sig { params(user: User, mangled: String).void }
    private_class_method def self.log_mangling(user, mangled)
      GitHub.dogstats.count("spark.runtime.naming.user_collision", 1)
      attrs = {
        "gh.actor.login": user.display_login,
        "mangled": mangled
      }
      GitHub.logger.info("Spark Runtime mangled a user login", attrs)

      payload = Workbench::TelemetryInstrumenter::Payload.from_api(
        restricted: false,
        current_user: user,
        event_type: "spark.name_mangled",
        request_id: GitHub.context[:request_id] || "",
        session_id: GitHub.context[:actor_session]&.to_s || "",
        spark_id: "",
        context: attrs,
        timestamp: Time.now,
      )
      GlobalInstrumenter.instrument(Workbench::Events::GENERIC, payload)
    end
  end
end
