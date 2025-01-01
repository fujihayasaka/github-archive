# typed: true
# frozen_string_literal: true

##
## Routes to this file are defined at: config/routes/copilot.rb
## Tests for this are at: test/integration/copilot/spark_runtime/runtime_name_controller_test.rb
##

class Copilot::Workbench::RuntimeNameController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch

  def check_name  # rubocop:todo GitHub/UseRestfulActions
    data = JSON.parse(request.raw_post)
    desired_spark_friendly_name = data["desired_spark_friendly_name"]
    permanent_name = data["permanent_name"]

    generated_name = SparkRuntime::Naming.convert_name(desired_spark_friendly_name)
    return render json: { generatedName: generated_name, errors: "Name is empty" }, status: 422 if generated_name.blank?

    already_exists = Spark::RuntimeApp.where(user_id: current_user.id, friendly_name: generated_name).
      where.not(permanent_name:).
      exists?

    respond_to do |format|
      format.json do
        if already_exists
          return render json: { generatedName: generated_name, errors: "is already used" }, status: 422
        else
          return render json: { generatedName: generated_name }
        end
      end
    end
  end
end
