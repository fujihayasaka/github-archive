# typed: true
# frozen_string_literal: true

module MsRest
  # Base module for Ruby serialization and deserialization.
  #
  # Provides methods to serialize Ruby object into Ruby Hash and
  # to deserialize Ruby Hash into Ruby object.
  module Serialization
    class Serialization

      def serialize_primary_type(mapper, object)
        mapper_type = mapper[:type][:name]
        payload = nil
        case mapper_type
          when 'Number', 'Double', 'String', 'Date', 'Boolean', 'Object', 'Stream'
            payload = object != nil ? object : nil
          when  'Enum'
            unless object.nil?
              unless enum_is_valid(mapper, object)
                fail ValidationError, "Enum #{mapper[:type][:module]} does not contain #{object.to_s}, but trying to send it to the server."
              end
            end
            payload = object != nil ? object : nil
          when 'ByteArray'
            payload = Base64.strict_encode64(object.pack('c*'))
          when 'DateTime'
            payload = object.new_offset(0).strftime('%FT%TZ')
          when 'DateTimeRfc1123'
            payload = object.new_offset(0).strftime('%a, %d %b %Y %H:%M:%S GMT')
          when 'UnixTime'
            payload = object.new_offset(0).strftime('%s') unless object.nil?
          when 'Base64Url'
            payload = Base64.urlsafe_encode64(object.pack('c*'), padding: false)
        end
        payload
      end

      def serialize(mapper, object)
        object_name = mapper[:serialized_name]

        # Set defaults
        unless mapper[:default_value].nil?
          object = mapper[:default_value] if object.nil?
        end
        object = mapper[:default_value] if mapper[:is_constant]

        validate_constraints(mapper, object, object_name)

        if !mapper[:required] && object.nil?
          return object
        end

        payload = Hash.new
        mapper_type = mapper[:type][:name]
        if !mapper_type.match(/^(Number|Double|ByteArray|Boolean|Date|DateTime|DateTimeRfc1123|UnixTime|Enum|String|Object|Stream|Base64Url)$/i).nil?
          payload = serialize_primary_type(mapper, object)
        elsif !mapper_type.match(/^Dictionary$/i).nil?
          payload = serialize_dictionary_type(mapper, object, object_name)
        elsif !mapper_type.match(/^Composite$/i).nil?
          payload = serialize_composite_type(mapper, object, object_name)
        elsif !mapper_type.match(/^Sequence$/i).nil?
          payload = serialize_sequence_type(mapper, object, object_name)
        end
        payload
      end
    end
  end
end

module MsRestAzure
  module AzureEnvironments
    AzureUSNatCloud = AzureEnvironments::AzureEnvironment.new({
      name: "AzureUSNatCloud",
      portal_url: "https://portal.azure.eaglex.ic.gov/",
      publishing_profile_url: "https://manage.eaglex.ic.gov/publishsettings/index",
      management_endpoint_url: "https://management.core.eaglex.ic.gov",
      resource_manager_endpoint_url: "https://usnatwest.management.azure.eaglex.ic.gov",
      sql_management_endpoint_url: "https://management.core.eaglex.ic.gov:8443/",
      sql_server_hostname_suffix: ".database.cloudapi.eaglex.ic.gov",
      gallery_endpoint_url: "https://gallery.cloudapi.eaglex.ic.gov/",
      active_directory_endpoint_url: "https://login.microsoftonline.eaglex.ic.gov/",
      active_directory_resource_id: "https://management.azure.eaglex.ic.gov/",
      active_directory_graph_resource_id: "https://graph.cloudapi.eaglex.ic.gov/",
      active_directory_graph_api_version: "2013-04-05",
      storage_endpoint_suffix: ".core.eaglex.ic.gov",
      key_vault_dns_suffix: ".vault.cloudapi.eaglex.ic.gov",
      datalake_store_filesystem_endpoint_suffix: "N/A",
      datalake_analytics_catalog_and_job_endpoint_suffix: "N/A",
    })

    AzureUSSecCloud = AzureEnvironments::AzureEnvironment.new({
      name: "AzureUSSecCloud",
      portal_url: "https://portal.azure.microsoft.scloud/",
      publishing_profile_url: "https://manage.microsoft.scloud/publishsettings/index",
      management_endpoint_url: "https://management.core.microsoft.scloud",
      resource_manager_endpoint_url: "https://management.azure.microsoft.scloud",
      sql_management_endpoint_url: "https://management.core.microsoft.scloud:8443/",
      sql_server_hostname_suffix: ".database.cloudapi.microsoft.scloud",
      gallery_endpoint_url: "https://gallery.cloudapi.microsoft.scloud/",
      active_directory_endpoint_url: "https://login.microsoftonline.microsoft.scloud/",
      active_directory_resource_id: "https://management.azure.microsoft.scloud/",
      active_directory_graph_resource_id: "https://graph.cloudapi.microsoft.scloud",
      active_directory_graph_api_version: "2013-04-05",
      storage_endpoint_suffix: ".core.microsoft.scloud",
      key_vault_dns_suffix: ".vault.cloudapi.microsoft.scloud",
      datalake_store_filesystem_endpoint_suffix: "N/A",
      datalake_analytics_catalog_and_job_endpoint_suffix: "N/A",
    })
  end
end
