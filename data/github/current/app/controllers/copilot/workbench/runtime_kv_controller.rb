# typed: true
# frozen_string_literal: true

##
## Routes to this file are defined at: config/routes/copilot.rb
## Tests for this are at: test/integration/copilot/workbench/runtime_kv_controller_test.rb
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

  before_action :find_runtime_app!

  def index
    values = ::SparkRuntime::Kv.all_keys(current_user, @runtime_app)
    if values.nil?
      render_404
      return
    end

    respond_to do |format|
      format.json do
        render json: values, status: :ok
      end
    end
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    respond_to do |format|
      format.json do
        render status: e.status, json: { error: e.message }
      end
    end
  end

  def show
    key = params[:key]

    value = ::SparkRuntime::Kv.read_key(current_user, @runtime_app, key)

    respond_to do |format|
      format.text do
        render plain: value, status: 200
      end
    end
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    respond_to do |format|
      format.text do
        render status: e.status, plain: e.message
      end
    end
  end

  def update
    key = params[:key]

    new_value = request.body.read
    ::SparkRuntime::Kv.write_key(current_user, @runtime_app, key, new_value)
    respond_to do |format|
      format.text do
        render status: 204, plain: "Updated"
      end
    end
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    respond_to do |format|
      format.text do
        render status: e.status, plain: e.message
      end
    end
  rescue SparkRuntime::Kv::SparkRuntimeKvReadOnlyError => e
    respond_to do |format|
      format.text do
        render status: 403, plain: e.message
      end
    end
  end

  def destroy
    key = params[:key]

    ::SparkRuntime::Kv.delete_key(current_user, @runtime_app, key)
    respond_to do |format|
      format.json do
        render status: 204, plain: ""
      end
    end
  rescue SparkRuntime::Kv::SparkRuntimeKvError => e
    respond_to do |format|
      format.json do
        render status: e.status, json: { error: e.message }
      end
    end
  rescue SparkRuntime::Kv::SparkRuntimeKvReadOnlyError => e
    respond_to do |format|
      format.json do
        render status: 403, json: { error: e.message }
      end
    end
  end

  private

  def find_runtime_app!
    app_name = params[:id]
    return render_404 unless app_name
    @runtime_app = Spark::RuntimeApp.find_by(user: @current_user, permanent_name: app_name)
    render_404 unless @runtime_app
  end
end
