# typed: strict
# frozen_string_literal: true

# This module defines the approach that we use to update the value of a field for a particular project item.
#
# It coordinates synchronous writes to two datastores:
#
#   1. A required write to MySQL, which ensures the durability of the data. If this write fails, then we will also
#      fail the overall PUT/POST/DELETE web request.
#   2. An optional write to Elasticsearch, which makes the write available for low-latency reads. If this write fails,
#      we will still allow the web request to succeed, but the data will not be available to read until the automatic
#      failure recovery process has been completed.
#
# For more information on the architecture of using two datastores please see:
# https://github.com/github/projects-platform/blob/main/docs/initiatives/projects-without-limits/data-architecture.md
module MemexProjectColumn::Interface::Writeable
  extend T::Helpers
  interface!

  # Represents the outcome of a write to just one datastore.
  class PartialResult < T::Struct

    class Error < T::Struct
      const :attribute, Symbol, default: :base
      const :message, String
    end

    const :error, T.nilable(Error)

    sig { returns(PartialResult) }
    def self.success = self.new

    sig { params(message: String, attribute: Symbol).returns(PartialResult) }
    def self.failure(message, attribute: :base) = self.new(error: Error.new(message:, attribute:))

    sig { returns(T::Boolean) }
    def succeeded? = error.nil?

    sig { returns(T::Boolean) }
    def failed? = !succeeded?

    # Hide the constructor from the public interface; the .success and .failure factory methods should used instead.
    private_class_method :new
  end

  # Represents the overall outcome of the write.
  class Result
    STAT = "memex_project_column.interface.writeable.result"

    sig { returns(PartialResult) }
    attr_reader :mysql

    sig { returns(T.nilable(PartialResult)) }
    attr_reader :elasticsearch

    sig { params(mysql: PartialResult, elasticsearch: T.nilable(PartialResult)).void }
    def initialize(mysql:, elasticsearch: nil)
      @mysql = mysql
      @elasticsearch = elasticsearch

      GitHub.dogstats.increment(
        STAT,
        tags: [
          "mysql_success:#{mysql.succeeded?}",
          "elasticsearch_success:#{elasticsearch ? elasticsearch.succeeded? : 'n/a'}",
        ]
      )
    end

    sig { returns(Result) }
    def self.success = self.new(mysql: PartialResult.success, elasticsearch: PartialResult.success)
  end

  # Represents an update that we will submit to Elasticsearch as part of a bulk update request.
  class BulkUpdateAction < T::Struct
    const :body, T::Hash[T.untyped, T.untyped]
    const :params, T::Hash[T.untyped, T.untyped]
  end

  module ClassMethods
    extend T::Helpers
    abstract!

    # Returns true if this field can be updated by a user from a Projects client or API.
    #
    # Some fields are read-only in Projects: they can only be updated by other systems (e.g. `linked-pull-requests`).
    # Those fields should return false from this method.
    sig { abstract.returns(T::Boolean) }
    def writeable?; end

    # Returns true if this field can only be initialized or updated with a definite (i.e. non-nil) value.
    sig { abstract.returns(T::Boolean) }
    def value_required?; end
  end

  mixes_in_class_methods(ClassMethods)

  NOT_FOUND = 404
  DOCUMENT_MISSING_STAT = "memex_project_column.interface.writeable.document_missing"

  sig { params(error: ElastomerClient::Client::RequestError, context: T.nilable(String)).returns(PartialResult) }
  def self.rescue_client_error(error:, context: nil)
    if error.try(:status) == NOT_FOUND
      tags = []
      tags << "context:#{context}" if context.present?
      GitHub.dogstats.increment(DOCUMENT_MISSING_STAT, tags:)
    else
      Failbot.report(error)
    end

    PartialResult.failure(error.message)
  end

  # Performs a write to MySQL (and, optionally, to Elasticsearch) to persist a new value for a particular field on
  # an item.
  #
  # This method has a default implementation in MemexProjectColumn::Field::Base that is suitable for most field types;
  # integrators should rely on that default implementation whenever possible.
  #
  # @param item The project item whose field we want to update.
  # @param new_value The new value that we want to set for the field. The static type of this value is determined by
  #   the Field subclass.
  # @param actor The user who is performing the update.
  # @param suppress_hydro_events Whether or not to skip instrumenting a Hydro event for this update. This should be
  #   used when the caller will manage the instrumentation of Hydro events themselves, typically because they are
  #   issuing multiple write requests within a single web request or background job (e.g. for a bulk update API
  #   endpoint).
  # @param skip_elasticsearch_updates Whether or not to skip writing to Elasticsearch. Much like
  #   `suppress_hydro_events`, this should be used when the caller wants to manage writing to Elasticsearch themselves
  #   in order to preserve efficiency.
  sig do
    abstract
    .params(
      item: MemexProjectItem,
      new_value: T.untyped,
      actor: User,
      suppress_hydro_events: T::Boolean,
      skip_elasticsearch_updates: T::Boolean,
    )
    .returns(Result)
  end
  def update_field_value(item:, new_value:, actor:, suppress_hydro_events: false, skip_elasticsearch_updates: false); end

  # Returns an object that describes how to submit an update for this item as part of a Bulk API request to
  # Elasticsearch.
  #
  # In order for this method to work correctly, the new value of the field for the given item must already have been
  # persisted to MySQL.
  #
  # This method has a default implementation in MemexProjectColumn::Field::Base that is suitable for most field types;
  # integrators should rely on that default implementation whenever possible.
  #
  # @param item The project item whose field we want to update.
  sig { abstract.params(item: MemexProjectItem).returns(T.nilable(BulkUpdateAction)) }
  def elasticsearch_bulk_update_action(item); end

  # Performs a write to MySQL to persist a new value for a particular field on an item.
  #
  # This write must succeed for the overall update operation to be considered successful.
  #
  # @param item The project item whose field we want to update.
  # @param new_value The new value that we want to set for the field. The static type of this value is determined by
  #   the Field subclass.
  # @param actor The user who is performing the update.
  # @param suppress_hydro_events Whether or not to skip instrumenting a Hydro event for this update. This should be
  #   used when the caller will manage the instrumentation of Hydro events themselves, typically because they are
  #   issuing multiple write requests within a single web request or background job (e.g. for a bulk update API
  #   endpoint).
  sig do
    abstract
    .params(item: MemexProjectItem, new_value: T.untyped, actor: User, suppress_hydro_events: T::Boolean)
    .returns(PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:); end

  # Performs a write to Elasticsearch to persist a new value for a particular field on an item.
  #
  # This write is optional. If it fails we will still allow the overall update operation to succeed, but the data will
  # not be available to read until the automatic failure recovery process has been completed.
  #
  # In order for this method to work correctly, the new value of the field for the given item must already have been
  # persisted to MySQL.
  #
  # @param item The project item whose field we want to update.
  # @param new_value The new value that we want to set for the field. The static type of this value is determined by
  #   the Field subclass.
  # @param actor The user who is performing the update.
  sig { abstract.params(item: MemexProjectItem, new_value: T.untyped, actor: User).returns(T.nilable(PartialResult)) }
  private def update_elasticsearch_field_value(item:, new_value:, actor:); end
end
