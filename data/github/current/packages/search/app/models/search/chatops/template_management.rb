# typed: true
# frozen_string_literal: true

module Search
  module Chatops
    class TemplateManagement

      VALID_COMMANDS = Set.new %w[create promote delete]

      # Create a new RepairIndex and execute the desired command.
      #
      # command       - The command to execute: list, start, stop, status, reset
      # template_name - The name of the search index to repair
      # opts          - Options hash to pass to the command
      #
      # Returns the response message.
      def self.run(command:, template_name:, **opts)
        validate_command! command
        self.new(template_name).public_send(command, **opts)
      rescue ArgumentError => err
        err.message
      end

      # Validate that the given `command` is in our list of allowed repair
      # commands.
      #
      # Raises RuntimeError on unknown repair commands
      def self.validate_command!(command)
        return if VALID_COMMANDS.include? command.to_s
        raise RuntimeError, "Unknown template command #{command.inspect}"
      end

      attr_reader :template_name

      # Create a new RepairIndexScript for the search index identified by name.
      #
      # template_name - The name of the search index template to manage
      #
      def initialize(template_name)
        @template_name = template_name
      end

      # Internal: Create a new search template on the given cluster.
      #
      # cluster:  Name of the search cluster where the template is to be created
      # writable: Boolean indicating that the tempmlate is writable
      # primary:  Boolean indicating that this should be a primary template
      #
      # Examples
      #
      #   .search template create audit_log auditlogsearch2
      #   .search template create audit_log-42 auditlogsearch2 --writable true --primary true
      #
      def create(cluster: "default", writable: true, primary: false)
        sitc = SearchIndexTemplateConfiguration.find_by(fullname: template_name)
        if sitc && sitc.exists?
          return "Search index template #{template_name.inspect} already exists"
        elsif sitc
          sitc.create_template
          return "Search index template #{template_name.inspect} was created on search cluster #{sitc.cluster.inspect}"
        end

        index_class = Elastomer.env.lookup_index(template_name)
        fullname = Elastomer.router.next_available_template_name(index_class)

        sitc = SearchIndexTemplateConfiguration.new \
            fullname:    fullname,
            cluster:     cluster,
            is_writable: writable,
            is_primary:  primary

        sitc.delete_template if sitc.exists?
        sitc.save!

        "Search index template #{fullname.inspect} was successfully created on search cluster #{cluster.inspect}"

      rescue Elastomer::UnknownCluster
        "Unknown search cluster #{cluster.inspect}"
      end

      # Internal: Promote the search index tempalte to the primary role.
      #
      # Examples
      #
      #   .search template promote audit_log-1
      #
      def promote(**keyword_args)
        sitc = SearchIndexTemplateConfiguration.find_by(fullname: template_name)
        unless sitc && sitc.exists?
          return "Search index template #{template_name.inspect} does not exist"
        end

        if sitc.primary?
          return "Search index template #{template_name.inspect} is already the primary index"
        end

        if current_primary = Elastomer.router.primary_template(template_name)
          current_primary.remove_primary
        end

        sitc.add_primary
        "Search index template #{template_name.inspect} was successfully promoted"

      rescue Elastomer::Error, ElastomerClient::Error => err
        Failbot.report err
        "Got an error trying to do that: #{err.message}"
      end

      # Internal: Delete the search index template. The primary template cannot
      # be deleted unless the `force` flag is set to true.
      #
      # force: Boolean used to force deletion of the primary template
      #
      # Examples
      #
      #   .search template destroy audit_log-1
      #
      def delete(force: false, **keyword_args)
        sitc = SearchIndexTemplateConfiguration.find_by(fullname: template_name)
        unless sitc && sitc.exists?
          return "Search index template #{template_name.inspect} does not exist"
        end

        if sitc.primary? && !force
          return "The primary search index tempalte #{template_name.inspect} cannot be deleted\n" +
                 "Pass the `--force true` flag if you absolutely want to delete this template"
        end

        sitc.delete_template(force: force)
        sitc.destroy
        "Search index template #{template_name.inspect} was successfully destroyed"

      rescue Elastomer::Error, ElastomerClient::Error => err
        Failbot.report err
        "Got an error trying to do that: #{err.message}"
      end

      # Internal: Look up the template configuration given the fullname of the
      # template.
      #
      # Returns the SearchIndexTemplateConfiguration instance or `nil` if not found
      def lookup_template
        SearchIndexTemplateConfiguration.find_by(fullname: template_name)
      end
    end
  end
end
