# typed: true
# frozen_string_literal: true

##
## Routes to this file are defined at: config/routes/copilot.rb
## Tests for this are at: test/integration/copilot/spark_runtime/runtime_kv_controller_test.rb
##

class Copilot::Workbench::RuntimeKvController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries, only: [:index, :show]

  def index
    app_id = params[:id]

    values = ::SparkRuntime::Kv.all_keys(current_user, current_user.display_login, app_id)
    if values.nil?
      render_404
      return
    end

    respond_to do |format|
      format.json do
        render json: values, status: :ok
      end
    end
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    render_invalid_database
  end

  def show
    app_id = params[:id]
    key = params[:key]

    value = ::SparkRuntime::Kv.read_key(current_user, current_user.display_login, app_id, key)

    respond_to do |format|
      format.text do
        render plain: value, status: 200
      end
    end
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    render_invalid_database
  end

  def update
    app_id = params[:id]
    key = params[:key]

    new_value = request.body.read
    ::SparkRuntime::Kv.write_key(current_user, current_user.display_login, app_id, key, new_value)
    respond_to do |format|
      format.text do
        render status: 204, plain: "Updated"
      end
    end
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    render_invalid_database
  end

  def destroy
    app_id = params[:id]
    key = params[:key]

    ::SparkRuntime::Kv.delete_key(current_user, current_user.display_login, app_id, key)
    respond_to do |format|
      format.json do
        render status: 204, plain: ""
      end
    end
  rescue SparkRuntime::AcaUrls::InvalidUrlError
    render_invalid_database
  end

  private

  def render_invalid_database
    render json: { error: "Invalid database" }, status: :bad_request
  end
end
