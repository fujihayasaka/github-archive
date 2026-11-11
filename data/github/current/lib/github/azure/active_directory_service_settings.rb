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
    #
    # Class which represents an settings for Azure AD authentication.
    #
    class ActiveDirectoryServiceSettings

      # @return [String] auth token.
      attr_accessor :authentication_endpoint

      # @return [String] auth token.
      attr_accessor :token_audience

      #
      # Returns a set of properties required to login into Azure Cloud.
      #
      # @param azure_environment [AzureEnvironment] An instance of AzureEnvironment.
      # @return [ActiveDirectoryServiceSettings] settings required for authentication.
      def self.get_settings(azure_environment)
        settings = ActiveDirectoryServiceSettings.new
        settings.authentication_endpoint = azure_environment.active_directory_endpoint_url
        settings.token_audience = azure_environment.active_directory_resource_id
        settings
      end
    end
  end
end
