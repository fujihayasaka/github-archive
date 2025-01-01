# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaUserManagementClient < AcaBaseClient
    sig do
      params(
        current_user: User,
        spark_owner: Spark::RuntimeAppOwner,
        should_use_new_api: T::Boolean
      ).void
    end
    def initialize(current_user, spark_owner, should_use_new_api)
      client_url = if should_use_new_api
        SparkRuntime::AcaUrls.management_user_url_11(spark_owner.permanent_name)
      else
        SparkRuntime::AcaUrls.management_user_url(spark_owner.deploy_login)
      end

      super(
        current_user,
        client_url,
        GitHub.copilot_workbench_aca_management_token,
        "management_user"
      )

      @spark_owner = spark_owner
    end

    sig do
      returns(AcaResponse)
    end
    def put_user
      rescue_from_aca_errors(:put, "users") do
        connection = create_connection
        connection.put do |aca_request|
          # The `isLegacy` flag determines if the user should be segregated into the `.users.github.app` subdomain.
          # It's keyed off of a difference between the last seen login and the deploy login.

          aca_request.headers["Content-Type"] = "application/json"
          aca_request.body = {
            defaultAppName: nil,
            defaultDatabaseName: nil,
            customUserName: @spark_owner.deploy_login,
            isLegacy: @spark_owner.is_segregated?,
          }.to_json
        end
      end
    end
  end
end
