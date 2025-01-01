# typed: true
# frozen_string_literal: true

module Audit
  module Elastic
    class Adapter
      attr_accessor :index_name, :cluster
      attr_writer :index

      def initialize(index_name: nil, cluster: GitHub.es_audit_log_cluster)
        @index_name = index_name
        @cluster = cluster
      end

      def index
        Elastomer::Indexes::AuditLog.new(index_name, cluster)
      end

      def generate_index(time = nil)
        case time
        when String
          time
        when Array
          time.collect { |date| date.utc.strftime("#{index.name}-%Y-%m") }.join(",")
        when Integer
          indexes = []
          time.times do |i|
            indexes << T.cast((Time.now.utc - i.months), Time).strftime("#{index.name}-%Y-%m")
          end
          indexes.join(",")
        when :all
          index.name
        when Date
          time.strftime("#{index.name}-%Y-%m")
        when Time
          time.utc.strftime("#{index.name}-%Y-%m")
        else
          if test_env?
            index.name
          else
            (time || Time.now).utc.strftime("#{index.name}-%Y-%m")
          end
        end
      end

      # Public: Refreshes the ElasticSearch index.
      #
      # Returns the true if refreshed, false if not.
      def refresh_index(time = nil)
        index.refresh(index: generate_index(time))
      end

      # Drops and re-creates the ElasticSearch index.
      #
      # Returns true if reset, false if not.
      def reset_index(time = nil)
        drop_index(time)
        create_index(time)
      end

      # Public: Determines if the index already exists.
      #
      # Returns true if exists, false if not.
      def index_exists?(time = nil)
        index.exists?(index: generate_index(time))
      end

      # Drops the ElasticSearch index.
      #
      # Returns the Faraday::Response.
      def drop_index(time = nil)
        name = generate_index(time)
        index.delete(index: name) if index.exists?(index: name)
      end

      # Creates the ElasticSearch index.
      #
      # Returns the Faraday::Response.
      def create_index(time = nil)
        index.create(index: generate_index(time))
      end

      # Updates the ElasticSearch index.
      #
      # Returns the Faraday::Response.
      def update_index(time = nil, mapping = nil)
        mapping ||= index.class.mappings_hook.fetch(:audit_entry)

        index.update_mapping(:audit_entry, mapping, index: generate_index(time))
      end

      # Creates an alias to the index
      #
      # Return the Faraday::Response
      def create_index_alias(time = nil)
        index.cluster.update_aliases(index_alias_data(time))
      end

      def index_alias_data(time = nil)
        {
          add: {
            index: generate_index(time),
            alias: index.name,
          },
        }
      end

      # Gets all indices based on the alias name
      # This will be used to look up the indices that
      # match an audit-log alias like audit_log-2021-03
      # which should return an index like audit_log-1-2021-03-1
      #
      def get_cluster_index_for_alias(name)
        begin
          index.cluster.get_aliases({ name: name }).keys
        rescue ElastomerClient::Client::RequestError, ElastomerClient::Client::IndexNotFoundError
          nil
        end
      end

      # Gets all the audit_log named indices in a index cluster
      # that match the pattern "audit_log-1-2020-02-1"
      #
      def get_cluster_all_audit_log_indices
        index.cluster.indices.keys.select { |i| i =~ /\A#{index.name}-(\d+?)-(\d+?)-(\d+?)-(\d+?)\z/ }
      end

      def get_template
        index.template.get(template_options)
      end

      def create_template
        index.template.create(index.template_data, template_options)
      end

      def drop_template
        index.template.delete(template_options)
      end

      def template_exists?(name = nil)
        index.cluster.templates.key?(name || template_name)
      end

      def template_name
        "#{index.name}_template"
      end

      def template_options
        { template: template_name }
      end

      def test_env?
        Rails.env.test?
      end
    end
  end
end
