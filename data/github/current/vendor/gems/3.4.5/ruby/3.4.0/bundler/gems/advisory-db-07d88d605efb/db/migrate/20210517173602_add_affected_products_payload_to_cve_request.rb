# frozen_string_literal: true

class AddAffectedProductsPayloadToCVERequest < ActiveRecord::Migration[6.1]
  def change
    add_column :cve_requests, :affected_products_payload, :longblob
  end
end
