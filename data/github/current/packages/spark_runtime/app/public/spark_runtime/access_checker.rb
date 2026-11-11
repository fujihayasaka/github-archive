# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AccessChecker
    sig { params(runtime_app: T.nilable(Spark::RuntimeApp), user: User).void }
    def initialize(runtime_app, user)
      @runtime_app = runtime_app
      @user = user
    end

    # Creates an access checker from the app's permanent name.
    sig { params(permanent_name: String, user: User).returns(SparkRuntime::AccessChecker) }
    def self.from_app_name(permanent_name, user)
      runtime_app = Spark::RuntimeApp.find_by(permanent_name:)
      new(runtime_app, user)
    end

    sig { returns(T::Boolean) }
    def allowed?
      result = if @runtime_app
        decision = ::Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :view_deployed_spark,
          actor: @user,
          subject: @runtime_app,
        ).sync
        decision.allow?
      else
        false
      end

      GitHub.logger.info("spark_authentication",
        "gh.spark.id" => @runtime_app&.permanent_name,
        "gh.spark.result" => result,
        "gh.spark.runtime_app_id" => @runtime_app&.id,
        "gh.spark.visibility" => @runtime_app&.visibility,
        "gh.spark.visibility_organization_id" => @runtime_app&.visibility_organization_id,
        "gh.user.login" => @user.display_login,
      )

      result
    end
  end
end
