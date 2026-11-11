# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SocialExperienceInstrumentationJob < ApplicationJob
  queue_as :social_experience_instrumentation

  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  rescue_from(ActiveJob::DeserializationError) do |exception|
    GitHub.logger.info("ActiveJob::DeserializationError", {
      "error": exception.message,
      "code.namespace": "SocialExperienceInstrumentationJob",
      "code.function": "publish_query",
      "gh.request_id": GitHub.context[:request_id],
      "gh.controller": GitHub.context[:controller],
      "gh.action": GitHub.context[:controller_action],
      "gh.method": GitHub.context[:method],
      "gh.from": GitHub.context[:from],
      "gh.catalog_service": GitHub.context[:catalog_service],
      "gh.request_category": GitHub.context[:category],
    })
  end

  UNSCOPED_QUERY = "UNSCOPED"
  NOT_CROSS_ORG = "NO"
  MAYBE_CROSS_ORG = "MAYBE"
  IS_CROSS_ORG_UNKNOWN = "UNKNOWN"

  def initialize(*args, **kwargs)
    @request_id = GitHub.context[:request_id]
    @request_method = GitHub.context[:method] || GitHub.context[:request_method]
    @controller = GitHub.context[:controller]
    @action = GitHub.context[:controller_action]
    @from = GitHub.context[:from]
    @catalog_service = GitHub.context[:catalog_service]
    @request_category = GitHub.context[:category]

    super(*T.unsafe(args), **kwargs)
  end

  def perform(redacted_unique_queries = [])
    GitHub.logger.info("Processing #{redacted_unique_queries.count} queries", {
      "code.namespace": "SocialExperienceInstrumentationJob",
      "code.function": "perform",
      "gh.request_id": @request_id,
      "gh.controller": @controller,
      "gh.action": @controller_action,
      "gh.method": @request_method,
      "gh.from": @from,
      "gh.catalog_service": @catalog_service,
      "gh.request_category": @request_category,
    })

    redacted_unique_queries.each do |redacted_query|
      parsed_query = parse_redacted_sql(redacted_query[:redacted_sql])
      next if parsed_query.nil? || parsed_query[:query_parts].nil?

      table_name = parsed_query[:query_parts][:table_name]
      if !relevant_tables.include?(table_name)
        record_no_cross_shard_for_query(table_name, redacted_query) if redacted_query[:on_primary] == true
      else
        analysis = analyze_query(**parsed_query)
        record_maybe_cross_org_query(redacted_query, analysis)
      end
    end
  end

  private

  def parse_redacted_sql(redacted_sql)
    if redacted_sql.start_with?("INSERT INTO")
      {
        sql_operation: :insert,
        query_parts: GitHub::SQL::QueryTracking.parse_insert_query(redacted_sql)
      }
    elsif redacted_sql.start_with?("SELECT")
      {
        sql_operation: :select,
        query_parts: redacted_sql.match(
          /SELECT.+FROM\s+`?(?<table_name>\w+)`?.*?\s+WHERE\s+(?<where_clause>.+?)(?:\s+ORDER\s+BY|\s+GROUP\s+BY|\s+LIMIT|\z)/m
        )
      }
    elsif redacted_sql.start_with?("DELETE")
      {
        sql_operation: :delete,
        query_parts: redacted_sql.match(
          /DELETE.+FROM\s+`?(?<table_name>\w+)`?.*?\s+WHERE\s+(?<where_clause>.+?)(?:\s+ORDER\s+BY|\s+GROUP\s+BY|\s+LIMIT|\z)/m
        )
      }
    elsif redacted_sql.start_with?("UPDATE")
      {
        sql_operation: :update,
        query_parts: redacted_sql.match(
          /UPDATE\s+`?(?<table_name>\w+)`?.*?\s+SET.+?\s+WHERE\s+(?<where_clause>.+?)(?:\s+ORDER\s+BY|\s+GROUP\s+BY|\s+LIMIT|\z)/m
        )
      }
    end
  end

  def analyze_query(sql_operation:, query_parts:)
    if sql_operation == :insert
      analyze_insert_query(**query_parts)
    else
      analyze_where_clause_query(query_parts[:table_name], query_parts[:where_clause])
    end
  end

  def analyze_insert_query(table_name:, columns:, rows:)
    shard_key_config = cross_primary_tables_to_shard_keys[table_name]
    vitess_shard_key = shard_key_config["vitess_shard_key"]
    is_vitess_shard_key_missing = !columns.include?(vitess_shard_key)
    current_shard_keys = guess_current_shard_keys_from_insert(columns, rows, vitess_shard_key)
    org_ids = guess_owners(table_name: table_name, shard_key_config: shard_key_config, current_shard_keys: current_shard_keys, is_insert: true, columns: columns, rows: rows)

    {
      table_name: table_name,
      vitess_shard_key: vitess_shard_key,
      discoverable_shard_keys: current_shard_keys.uniq.sort,
      discoverable_org_ids: org_ids.uniq.sort,
      vitess_shard_key_is_missing: is_vitess_shard_key_missing,
    }
  end

  def guess_current_shard_keys_from_insert(columns, rows, shard_key)
    return [] if shard_key.nil?
    index = columns.index(shard_key)
    return [] if index.nil?
    rows.filter_map { |values| values[index] }.uniq.sort.map(&:strip)
  end

  def guess_owners(table_name:, shard_key_config:, current_shard_keys:, is_insert:, columns: [], rows: [], where_clause: "")
    owner_mapping = shard_key_config["owner_mapping"]
    vitess_shard_key = shard_key_config["vitess_shard_key"]

    return [] if owner_mapping.nil?
    return current_shard_keys.map(&:to_i) if owner_mapping == vitess_shard_key

    if is_insert
      guessed_from_query = guess_current_shard_keys_from_insert(columns, rows, owner_mapping).map(&:to_i)
    else
      guessed_from_query = guess_current_shard_keys_from_where(where_clause, owner_mapping).map(&:to_i)
    end

    if guessed_from_query.any?
      guessed_from_query
    elsif owner_mapping == "repository.owner_id" || owner_mapping == "source.repository.owner_id"
      Repository.where(id: current_shard_keys.map(&:to_i)).pluck(:owner_id).uniq.sort
    else
      []
    end
  end

  def analyze_where_clause_query(table_name, where_clause)
    shard_key_config = cross_primary_tables_to_shard_keys[table_name]
    vitess_shard_key = shard_key_config["vitess_shard_key"]

    is_vitess_shard_key_missing = !(where_clause.include?("`#{table_name}`.`#{vitess_shard_key}`") || where_clause.include?("#{table_name}.#{vitess_shard_key}"))
    if is_vitess_shard_key_missing
      current_shard_keys = guess_current_shard_keys_from_other_keys_in_where(table_name, where_clause)
    else
      current_shard_keys = guess_current_shard_keys_from_where(where_clause, vitess_shard_key)
    end
    org_ids = guess_owners(table_name: table_name, shard_key_config: shard_key_config, current_shard_keys: current_shard_keys, is_insert: false, where_clause: where_clause)

    {
      table_name: table_name,
      vitess_shard_key: vitess_shard_key,
      discoverable_shard_keys: current_shard_keys.uniq.sort,
      discoverable_org_ids: org_ids.uniq.sort,
      vitess_shard_key_is_missing: is_vitess_shard_key_missing
    }
  end

  def guess_current_shard_keys_from_where(where_clause, vitess_shard_key)
    in_match = where_clause.match(/(?:`?\w+`?\.)?`?#{vitess_shard_key}`?\s+IN\s+\((?<values>[^)]+)\)/)
    if in_match
      return in_match[:values].split(",").map(&:strip)
    end

    eq_match = where_clause.match(/(?:`?\w+`?\.)?`?#{vitess_shard_key}`?\s*=\s*(?<value>\d+)/)
    return [eq_match[:value].strip] if eq_match

    []
  end

  # some commonly seen queries missing shard keys, so we can try to get shards from other keys in the where clause
  # based on queries we have already logged
  # can be filled in more later based on which queries are missing shard keys
  def guess_current_shard_keys_from_other_keys_in_where(table_name, where_clause)
    if where_clause.include?("`#{table_name}`.`issue_id`") || where_clause.include?("#{table_name}.issue_id")
      issue_id_match = where_clause.match(/`?#{table_name}`?\.`?issue_id`?\s*(?:IN\s*\((?<issue_ids>[^)]+)\)|=\s*(?<issue_ids>\d+))/)
      return [] unless issue_id_match

      issue_ids = issue_id_match[:issue_ids].split(",").map(&:to_i)
      Issue.where(id: issue_ids).pluck(:repository_id).uniq.sort
    end
    []
  end

  def cross_primary_tables_to_shard_keys
    @cross_primary_tables_to_shard_keys ||= JSON.parse(File.read(Rails.root.join("config", "data_partitioning", "vitess_tables.json")))
  end

  def relevant_tables
    @relevant_tables ||= cross_primary_tables_to_shard_keys.keys
  end

  def record_maybe_cross_org_query(redacted_query, analysis)
    message = {
      request_id: @request_id,
      redacted_sql: redacted_query[:redacted_sql],
      digest_sql: redacted_query[:digested_sql],
      transaction_uuid: redacted_query[:transaction_uuid],
      on_primary: redacted_query[:on_primary],
      connection_class_name: redacted_query[:connection_class_name],
      connection_class_role: redacted_query[:connection_class_role],
      table_name: analysis[:table_name],
      vitess_shard_key: analysis[:vitess_shard_key],
      vitess_shard_key_is_missing: analysis[:vitess_shard_key_is_missing],
      discoverable_shard_keys: analysis[:discoverable_shard_keys],
      discoverable_org_ids: analysis[:discoverable_org_ids],
      is_cross_org: MAYBE_CROSS_ORG,
    }

    Hydro::PublishRetrier.publish(
      message,
      schema: "github.database.v1.TrackedQuery",
      partition_key: @from
    )
  end

  # we still want to log queries even if they are not currently vitess-sharded
  # because we want to understand cross-cluster primary access as well
  def record_no_cross_shard_for_query(table_name, redacted_query)
    message = {
      request_id: @request_id,
      redacted_sql: redacted_query[:redacted_sql],
      digest_sql: redacted_query[:digested_sql],
      transaction_uuid: redacted_query[:transaction_uuid],
      on_primary: redacted_query[:on_primary],
      connection_class_name: redacted_query[:connection_class_name],
      connection_class_role: redacted_query[:connection_class_role],
      table_name: table_name,
      discoverable_shard_keys: [],
      discoverable_org_ids: [],
      is_cross_org: NOT_CROSS_ORG,
    }

    Hydro::PublishRetrier.publish(
      message,
      schema: "github.database.v1.TrackedQuery",
      partition_key: @from
    )
  end
end
