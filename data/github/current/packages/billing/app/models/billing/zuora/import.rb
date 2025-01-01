# typed: strict
# frozen_string_literal: true

class Billing::Zuora::Import
  extend T::Sig

  # Public: Returns the successful file imports with the associated filename.
  # Successful imports are where the status is not Canceled or Failed
  sig { params(name: String).returns(T::Array[T.attached_class]) }
  def self.successful_imports(name:)
    response = GitHub.zuorest_client.query_action queryString: <<-ZOQL
      select Id, Status, Name from Import
       where Name = '#{name}'
        and Status != 'Canceled'
        and Status != 'Failed'
    ZOQL

    create_imports_from_zuora(response)
  end

  sig { params(id: String).returns(T.attached_class) }
  def self.find(id)
    response = GitHub.zuorest_client.get_import(id)
    new(response)
  end

  sig { params(import_attributes: T::Hash[String, T.untyped]).void }
  def initialize(import_attributes)
    @attributes = import_attributes
  end

  sig { returns(String) }
  def id
    attributes["Id"]
  end

  sig { returns(String) }
  def status
    attributes["Status"]
  end

  sig { returns(String) }
  def name
    attributes["Name"]
  end

  sig { returns(String) }
  def status_reason
    attributes["StatusReason"]
  end

  # Public: Returns url to check the import status
  sig { returns(String) }
  def zuora_status_url
    "/v1/usage/#{id}/status"
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :attributes

  # Private: Takes a query response from zuora and creates imports
  sig { params(response: T::Hash[String, T.untyped]).returns(T::Array[T.attached_class]) }
  def self.create_imports_from_zuora(response)
    response
      .fetch("records", [])
      .compact
      .map { |record| new(record) }
  end
  private_class_method :create_imports_from_zuora
end
