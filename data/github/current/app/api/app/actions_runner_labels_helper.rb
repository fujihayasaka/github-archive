# typed: false
# frozen_string_literal: true

module Api::App::ActionsRunnerLabelsHelper
  include Api::App::TwirpHelpers
  include Api::App::ReceiveSchemaWithOpenApi

  private

  def list_labels_for_runner(entity)
    # Verify the runner exists
    runner = handle_runner_errors do
      Actions::Runner.get!(entity, params[:runner_id].to_i)
    end

    deliver_error! 404 unless runner

    deliver :actions_runner_labels_hash, { labels: runner.labels }
  end

  def add_custom_labels_to_runner(entity)
    # Verify the runner exists before validating the input
    runner = handle_runner_errors do
      Actions::Runner.get!(entity, params[:runner_id].to_i)
    end

    deliver_error! 404 unless runner

    # Validate the input
    data = receive_with_openapi

    # Minorly sanitize the labels being requested for addition
    requested_label_names = data["labels"].map(&:strip).uniq { |name| name.downcase }

    succeeded = begin
      runner.add_custom_labels!(requested_label_names)
    rescue Actions::Runner::RunnerServiceError => e
      deliver_error! e.status, { message: e.message }
    end

    deliver_error! 500, { message: "Failed to add labels to runner" } unless succeeded

    deliver :actions_runner_labels_hash, { labels: runner.labels }
  end

  def replace_all_custom_labels_for_runner(entity)
    # Verify the runner exists before validating the input
    runner = handle_runner_errors do
      Actions::Runner.get!(entity, params[:runner_id].to_i)
    end

    deliver_error! 404 unless runner

    # Validate the input
    data = receive_with_openapi

    # Minorly sanitize the labels being requested for addition
    requested_label_names = data["labels"].map(&:strip).uniq { |name| name.downcase }

    succeeded = begin
      runner.replace_all_custom_labels!(requested_label_names)
    rescue Actions::Runner::RunnerServiceError => e
      deliver_error! e.status, { message: e.message }
    end

    deliver_error! 500, { message: "Failed to set labels for runner" } unless succeeded

    deliver :actions_runner_labels_hash, { labels: runner.labels }
  end

  def remove_all_custom_labels_from_runner(entity)
    # Verify the runner exists
    runner = begin
      Actions::Runner.get!(entity, params[:runner_id].to_i)
    rescue Actions::Runner::RunnerServiceError => e
      deliver_error! e.status, { message: e.message }
    end

    deliver_error! 404 unless runner

    succeeded = begin
      runner.remove_all_custom_labels!
    rescue Actions::Runner::RunnerServiceError => e
      deliver_error! e.status, { message: e.message }
    end

    deliver_error! 500, { message: "Failed to remove labels for runner" } unless succeeded

    deliver :actions_runner_labels_hash, { labels: runner.labels }
  end

  def remove_custom_label_from_runner(entity)
    # Verify the runner exists before validating the input
    runner = handle_runner_errors do
      Actions::Runner.get!(entity, params[:runner_id].to_i)
    end

    deliver_error! 404 unless runner

    # Minorly sanitize the label being requested for removal
    label_name = params[:name].to_s.strip

    succeeded = begin
      runner.remove_custom_label!(label_name)
    rescue Actions::Runner::RunnerServiceError => e
      deliver_error! e.status, { message: e.message }
    end

    deliver_error! 500, { message: "Failed to remove label for runner" } unless succeeded

    deliver :actions_runner_labels_hash, { labels: runner.labels }
  end

  def handle_runner_errors
    raise ArgumentError, "A block must be passed to #{__method__}" unless block_given?

    begin
      yield
    rescue Actions::Runner::RunnerServiceError => e
      deliver_error! e.status, { message: e.message }
    end
  end
end
