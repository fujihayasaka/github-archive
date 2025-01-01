# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AccessChecker
    sig { params(permanent_name: String, user: User).void }
    def initialize(permanent_name, user)
      @permanent_name = permanent_name
      @user = user
    end

    sig { returns(T::Boolean) }
    def allowed?
      runtime_app = Spark::RuntimeApp.find_by(permanent_name: @permanent_name)

      result = false
      if @user.feature_enabled?(:spark_view_fgp)
        decision = ::Platform::Loaders::Permissions::BatchAuthorize.load(
          action: :view_deployed_spark,
          actor: @user,
          subject: runtime_app,
        ).sync
        result = decision.allow?
      else
        result = case runtime_app&.visibility
        when "only_owner"
          runtime_app&.user == @user
        when "github"
          @user.present?
        else
          false
        end
      end

      GitHub.logger.info("spark_authentication",
        "gh.spark.id" => @permanent_name,
        "gh.spark.visibility" => runtime_app&.visibility,
        "gh.spark.result" => result,
        "gh.spark.used_fgp" => @user.feature_enabled?(:spark_view_fgp),
        "gh.user.login" => @user.display_login,
      )

      result
    end
  end
end
