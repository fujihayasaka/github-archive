# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class UserPropensityImportJob < ApplicationJob
  queue_as :user_propensity_import

  retry_on_dirty_exit

  BATCH_SIZE = 100

  # Perform the data import and save into KV cache
  sig { override.void }
  def perform
    return unless GitHub.flipper[:user_propensity_job].enabled?

    # Batching user propensity Presto query
    offset = 0

    loop do
      query = build_propensity_query(BATCH_SIZE, offset)
      query_start_time = Time.now.utc
      results = GitHub.presto.run_with_names(query)

      results ||= []

      break if results.empty?

      batch_perform(results)

      # Log the duration of all batches processed
      time_elapsed = GitHub::Dogstats.duration(query_start_time, Time.now.utc)
      GitHub.dogstats.distribution("customer_propensity_data.query_duration", time_elapsed)

      offset += BATCH_SIZE
    end
  end

  private

  sig { params(results: T::Array[T::Hash[String, T.untyped]]).void }
  def batch_perform(results)
    results.each do |result|
      key = "user_propensity/copilot_business/v1/#{result.fetch("user_id")}"

      value = {
        "user_id" => result.fetch("user_id"),
        "org_id" => result.fetch("org_id"),
        "org_login" => result.fetch("org_login"),
        "relationship_type" => result.fetch("relationship_type"),
        "org_propensity_score" => result.fetch("org_propensity_score").to_f,
        "group" => result.fetch("org_propensity_group"),
      }

      # Check if the propensity record exists in KV store
      existing_record = Site::KV.store.get(key).value { nil }

      # Save to the KV store if the existing record does not exist
      if existing_record.nil?
        create_propensity_record(value)
        next # Create the propensity record and move to the next iteration
      end

      # log when a duplicate record is found
      GitHub.logger.info("Duplicate propensity record found", {
        "code.namespace" => "UserPropensityImportJob",
        "code.function" => "batch_perform",
        "gh.user.id" => result.fetch("user_id"),
        "gh.organization" => result.fetch("org_login"),
        "gh.organization.id" => result.fetch("org_id"),
      })

      # Existing record exists at this point
      existing_record_data = JSON.parse(existing_record)

      if org_admin_status_updated?(existing_record_data, result)
        existing_record_data["relationship_type"] = result.fetch("relationship_type")
      end

      # If the group is different, update the group
      if org_propensity_group_updated?(existing_record_data, result)
        existing_record_data["group"] = result.fetch("org_propensity_group")
      end

      if org_propensity_score_increased?(existing_record_data, result)
        existing_record_data["org_propensity_score"] = result.fetch("org_propensity_score")
      end

      # Save the duplicate record to the KV store
      update_propensity_record(key, existing_record_data)
    end
  end

  sig { params(previous: T::Hash[String, T.untyped], current: T::Hash[String, T.untyped]).returns(T::Boolean) }
  def org_propensity_group_updated?(previous, current)
    current.fetch("org_propensity_group") != previous.fetch("group")
  end

  sig { params(previous: T::Hash[String, T.untyped], current: T::Hash[String, T.untyped]).returns(T::Boolean) }
  def org_propensity_score_increased?(previous, current)
    current.fetch("org_propensity_score").to_f > previous.fetch("org_propensity_score").to_f
  end

  sig { params(previous: T::Hash[String, T.untyped], current: T::Hash[String, T.untyped]).returns(T::Boolean) }
  def org_admin_status_updated?(previous, current)
    !org_admin?(previous) && org_admin?(current)
  end

  sig { params(member_data: T::Hash[String, T.untyped]).returns(T::Boolean) }
  def org_admin?(member_data)
    relationship = member_data.fetch("relationship_type", nil)
    relationship == "billing_manager" || relationship == "owner"
  end

  sig { params(limit: Integer, offset: Integer).returns(String) }
  def build_propensity_query(limit, offset)
    %Q(
        SELECT *
        FROM hive.data_science.copilot_experiment_project_phoenix_output_table_v3
        WHERE day = (
          SELECT MAX(day)
          FROM hive.data_science.copilot_experiment_project_phoenix_output_table_v3
        )
        AND is_treatment = TRUE
        OFFSET #{offset}
        LIMIT #{limit}
    )
  end

  sig { params(key: String, value: T::Hash[String, T.untyped]).void }
  def update_propensity_record(key, value)
    with_write do
      Site::KV.store.set(key, value.to_json, expires: 1.week.from_now)
    end
  end

  sig { params(data: T::Hash[String, T.untyped]).void }
  def create_propensity_record(data)
    User.throttle do
      user = User.find_by(id: data["user_id"])
      return unless user

      with_write do
        UserPropensity::CopilotBusiness.create(
          user: user,
          organization_id: data["org_id"],
          organization_login: data["org_login"],
          group: data["group"],
          relationship_type: data["relationship_type"],
          org_propensity_score: data["org_propensity_score"],
        )
      end
    end
  end
end
