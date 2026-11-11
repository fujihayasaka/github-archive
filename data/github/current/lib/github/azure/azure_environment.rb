# typed: true
# frozen_string_literal: true

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Corporation
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Portions Copyright (c) GitHub, Inc.

module GitHub
  module Azure
    module AzureEnvironments
      #
      # An instance of this class describes an environment in Azure
      #
      class AzureEnvironment

        # @return [String] the Environment name
        attr_reader :name

        # @return [String] the management portal URL
        attr_reader :portal_url

        # @return [String] the publish settings file URL
        attr_reader :publishing_profile_url

        # @return [String] the management service endpoint
        attr_reader :management_endpoint_url

        # @return [String] the resource management endpoint
        attr_reader :resource_manager_endpoint_url

        # @return [String] the sql server management endpoint for mobile commands
        attr_reader :sql_management_endpoint_url

        # @return [String] the dns suffix for sql servers
        attr_reader :sql_server_hostname_suffix

        # @return [String] the template gallery endpoint
        attr_reader :gallery_endpoint_url

        # @return [String] the Active Directory login endpoint
        attr_reader :active_directory_endpoint_url

        # @return [String] the resource ID to obtain AD tokens for
        attr_reader :active_directory_resource_id

        # @return [String] the Active Directory resource ID
        attr_reader :active_directory_graph_resource_id

        # @return [String] the Active Directory resource ID
        attr_reader :active_directory_graph_api_version

        # @return [String] the endpoint suffix for storage accounts
        attr_reader :storage_endpoint_suffix

        # @return [String] the KeyVault service dns suffix
        attr_reader :key_vault_dns_suffix

        # @return [String] the data lake store filesystem service dns suffix
        attr_reader :datalake_store_filesystem_endpoint_suffix

        # @return [String] the data lake analytics job and catalog service dns suffix
        attr_reader :datalake_analytics_catalog_and_job_endpoint_suffix

        # @return [Boolean] determines whether the authentication endpoint should be validated with Azure AD. Default value is true.
        attr_reader :validate_authority

        def initialize(options)
          required_properties = [:name, :portal_url, :management_endpoint_url, :resource_manager_endpoint_url, :active_directory_endpoint_url, :active_directory_resource_id]

          required_supplied_properties = required_properties & options.keys

          if required_supplied_properties.empty? || (required_supplied_properties & required_properties) != required_properties
            raise ArgumentError.new("#{required_properties} are the required properties but provided properties are #{options}")
          end

          required_supplied_properties.each do |prop|
            if options[prop].nil? || !options[prop].is_a?(String) || options[prop].empty?
              raise ArgumentError.new("Value of the '#{prop}' property must be of type String and non empty.")
            end
          end

          # Setting default to true
          @validate_authority = true

          options.each do |k, v|
            instance_variable_set("@#{k}", v) unless v.nil?
          end
        end
      end

      AzureCloud = AzureEnvironments::AzureEnvironment.new({
                                                          name: "AzureCloud",
                                                          portal_url: "https://portal.azure.com",
                                                          publishing_profile_url: "http://go.microsoft.com/fwlink/?LinkId=254432",
                                                          management_endpoint_url: "https://management.core.windows.net",
                                                          resource_manager_endpoint_url: "https://management.azure.com/",
                                                          sql_management_endpoint_url: "https://management.core.windows.net:8443/",
                                                          sql_server_hostname_suffix: ".database.windows.net",
                                                          gallery_endpoint_url: "https://gallery.azure.com/",
                                                          active_directory_endpoint_url: "https://login.microsoftonline.com/",
                                                          active_directory_resource_id: "https://management.core.windows.net/",
                                                          active_directory_graph_resource_id: "https://graph.windows.net/",
                                                          active_directory_graph_api_version: "2013-04-05",
                                                          storage_endpoint_suffix: ".core.windows.net",
                                                          key_vault_dns_suffix: ".vault.azure.net",
                                                          datalake_store_filesystem_endpoint_suffix: "azuredatalakestore.net",
                                                          datalake_analytics_catalog_and_job_endpoint_suffix: "azuredatalakeanalytics.net"
                                                      })
    end
  end
end
