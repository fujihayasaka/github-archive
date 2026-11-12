# frozen_string_literal: true

class AddStructuredSchemaForAdvisoryPayload < ActiveRecord::Migration[7.0]
  def change
    create_table :advisory_payloads do |t|
      t.string :summary, limit: 255, null: true
      t.text :description, null: true
      t.text :source_code_location, null: true
      t.string :severity, limit: 255, null: true
      t.string :cvss_v3, limit: 255, null: true
      t.references :payload_container, polymorphic: true, null: false, index: { unique: true }
      t.boolean :withdrawn, null: false, default: false
      t.timestamps
    end

    create_table :advisory_payload_cwe_ids do |t|
      t.bigint :advisory_payload_id, null: false
      t.string :cwe_id, limit: 9, null: true
      t.integer :index
      t.timestamps
      t.index [:advisory_payload_id, :index], unique: true, name: "index_advisory_payload_id"
    end

    create_table :advisory_payload_references do |t|
      t.bigint :advisory_payload_id, null: false
      t.text :url
      t.integer :index
      t.timestamps
      t.index [:advisory_payload_id, :index], unique: true, name: "index_advisory_payload_id"
    end

    create_table :advisory_payload_vulnerabilities do |t|
      t.bigint :advisory_payload_id, null: false
      t.string :package_ecosystem, limit: 255, null: true
      t.string :package_name, limit: 255, null: true
      t.integer :severity, null: true
      t.string :vulnerable_version_range, limit: 255, null: true
      t.string :first_patched_version, limit: 255, null: true
      t.integer :index
      t.timestamps
      t.index [:advisory_payload_id, :index], unique: true, name: "index_advisory_payload_id"
    end

    create_table :advisory_payload_vulnerability_affected_functions do |t|
      t.bigint :vulnerability_id, null: false
      t.text :fqn, null: true
      t.integer :fqn_version, null: true
      t.integer :index
      t.timestamps
      t.index [:vulnerability_id, :index], unique: true, name: "index_vulnerability_id"
    end

    create_table :advisory_payload_affected_function_search_keys do |t|
      t.bigint :affected_function_id, null: false
      t.text :search_key
      t.integer :index
      t.timestamps
      t.index [:affected_function_id, :index], unique: true, name: "index_affected_function_id"
    end
  end
end
